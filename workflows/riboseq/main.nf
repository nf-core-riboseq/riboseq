/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { BAM_DEDUP_STATS_SAMTOOLS_UMITOOLS as BAM_DEDUP_STATS_SAMTOOLS_UMITOOLS_GENOME        } from '../../subworkflows/nf-core/bam_dedup_stats_samtools_umitools/main'
include { BAM_DEDUP_STATS_SAMTOOLS_UMITOOLS as BAM_DEDUP_STATS_SAMTOOLS_UMITOOLS_TRANSCRIPTOME } from '../../subworkflows/nf-core/bam_dedup_stats_samtools_umitools/main'
include { FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS                                                 } from '../../subworkflows/nf-core/fastq_qc_trim_filter_setstrandedness/main'
include { BAM_DEDUP_UMI      } from '../../subworkflows/nf-core/bam_dedup_umi'
include { FASTQ_ALIGN_STAR   } from '../../subworkflows/nf-core/fastq_align_star'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { MULTIQC                                              } from '../../modules/nf-core/multiqc/main'
include { SAMTOOLS_SORT                                        } from '../../modules/nf-core/samtools/sort'
include { UMITOOLS_PREPAREFORRSEM as UMITOOLS_PREPAREFORSALMON } from '../../modules/nf-core/umitools/prepareforrsem'
include { RIBOTISH_QUALITY as RIBOTISH_QUALITY_RIBOSEQ         } from '../../modules/nf-core/ribotish/quality'
include { RIBOTISH_QUALITY as RIBOTISH_QUALITY_TISEQ           } from '../../modules/nf-core/ribotish/quality'
include { RIBOTISH_PREDICT as RIBOTISH_PREDICT_INDIVIDUAL      } from '../../modules/nf-core/ribotish/predict'
include { RIBOTISH_PREDICT as RIBOTISH_PREDICT_ALL             } from '../../modules/nf-core/ribotish/predict'
include { RIBOTRICER_PREPAREORFS                               } from '../../modules/nf-core/ribotricer/prepareorfs'
include { RIBOTRICER_DETECTORFS                                } from '../../modules/nf-core/ribotricer/detectorfs'
include { ANOTA2SEQ_ANOTA2SEQRUN                               } from '../../modules/nf-core/anota2seq/anota2seqrun'
include { QUANTIFY_PSEUDO_ALIGNMENT as QUANTIFY_STAR_SALMON    } from '../../subworkflows/nf-core/quantify_pseudo_alignment'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryMap         } from 'plugin/nf-schema'
include { samplesheetToList        } from 'plugin/nf-schema'
include { paramsSummaryMultiqc     } from '../../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML   } from '../../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText   } from '../../subworkflows/local/utils_nfcore_riboseq_pipeline'
include { validateInputSamplesheet } from '../../subworkflows/local/utils_nfcore_riboseq_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RIBOSEQ {

    take:
    ch_samplesheet      // channel: path(sample_sheet.csv)
    ch_contrasts_file   // channel: path(contrasts.csv)
    ch_versions         // channel: [ path(versions.yml) ]
    ch_fasta            // channel: path(genome.fasta)
    ch_gtf              // channel: path(genome.gtf)
    ch_fai              // channel: path(genome.fai)
    ch_chrom_sizes      // channel: path(genome.sizes)
    ch_transcript_fasta // channel: path(transcript.fasta)
    ch_star_index       // channel: path(star/index/)
    ch_salmon_index     // channel: path(salmon/index/)
    ch_bbsplit_index    // channel: path(bbsplit/index/)
    ch_rrna_fastas      // channel: path(fasta)
    ch_sortmerna_index  // channel: path(sortmerna/index/)

    main:

    /*
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        VALIDATE INPUTS
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    */

    // Check rRNA databases for sortmerna
    if (params.remove_ribo_rna) {
        ch_ribo_db = file(params.ribo_database_manifest)
        if (ch_ribo_db.isEmpty()) {exit 1, "File provided with --ribo_database_manifest is empty: ${ch_ribo_db.getName()}!"}
    } else {
        ch_ribo_db = Channel.empty()
    }

    // Check if file with list of fastas is provided when running BBSplit
    if (!params.skip_bbsplit && !params.bbsplit_index && params.bbsplit_fasta_list) {
        ch_bbsplit_fasta_list = file(params.bbsplit_fasta_list)
        if (ch_bbsplit_fasta_list.isEmpty()) {exit 1, "File provided with --bbsplit_fasta_list is empty: ${ch_bbsplit_fasta_list.getName()}!"}
    }

    // Check alignment parameters
    def prepareToolIndices  = []
    if (!params.skip_bbsplit) { prepareToolIndices << 'bbsplit' }
    if (params.remove_ribo_rna) { prepareToolIndices << 'sortmerna' }
    if (!params.skip_alignment) { prepareToolIndices << params.aligner }

    // Determine whether to filter the GTF or not
    def filterGtf =
        ((
            // Condition 1: Alignment is required and aligner is set
            !params.skip_alignment && params.aligner
        ) ||
        (
            // Condition 2: Transcript FASTA file is not provided
            !params.transcript_fasta
        )) &&
        (
            // Condition 3: --skip_gtf_filter is not provided
            !params.skip_gtf_filter
        )

    ch_multiqc_files = Channel.empty()

    //
    // Create input channel from input file provided through params.input
    //
    Channel
        .fromList(samplesheetToList(params.input, "${projectDir}/assets/schema_input.json"))
        .map {
            meta, fastq_1, fastq_2 ->
                if (!fastq_2) {
                    return [ meta.id, meta + [ single_end:true ], [ fastq_1 ] ]
                } else {
                    return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ] ]
                }
        }
        .groupTuple()
        .map {
            validateInputSamplesheet(it)
        }
        .set { ch_fastq }

    //
    // SUBWORKFLOW: preprocess reads for RNA-seq. Includes trimming,
    // contaminant removal, strandedness inference
    //

    // The subworkflow only has to do Salmon indexing if it discovers 'auto'
    // samples, and if we haven't already made one elsewhere
    salmon_index_available = params.salmon_index || (!params.skip_pseudo_alignment && params.pseudo_aligner == 'salmon')

    FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS (
        ch_fastq,
        ch_fasta,
        ch_transcript_fasta,
        ch_gtf,
        ch_salmon_index,
        ch_sortmerna_index,
        ch_bbsplit_index,
        ch_rrna_fastas,
        params.skip_bbsplit,
        params.skip_fastqc || params.skip_qc,
        params.skip_trimming,
        params.skip_umi_extract,
        !salmon_index_available,
        !params.sortmerna_index && params.remove_ribo_rna,
        params.trimmer,
        params.min_trimmed_reads,
        params.save_trimmed,
        params.remove_ribo_rna,
        params.with_umi,
        params.umi_discard_read,
        params.stranded_threshold,
        params.unstranded_threshold,
        params.skip_linting
    )

    ch_multiqc_files = ch_multiqc_files.mix(FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS.out.multiqc_files)
    ch_versions      = ch_versions.mix(FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS.out.versions)

    //
    // SUBWORKFLOW: align with STAR, produce both genomic and transcriptomic
    // alignments and run BAM_SORT_STATS_SAMTOOLS for each
    //

    FASTQ_ALIGN_STAR(
        FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS.out.reads,
        ch_star_index.map { [ [:], it ] },
        ch_gtf.map { [ [:], it ] },
        params.star_ignore_sjdbgtf,
        '',
        params.seq_center ?: '',
        ch_fasta.map { [ [:], it ] },
        ch_transcript_fasta.map { [ [:], it ] }
    )

    ch_genome_bam              = FASTQ_ALIGN_STAR.out.bam
    ch_genome_bam_index        = FASTQ_ALIGN_STAR.out.bai
    ch_transcriptome_bam       = FASTQ_ALIGN_STAR.out.orig_bam_transcript
    ch_transcriptome_bai       = FASTQ_ALIGN_STAR.out.bai_transcript
    ch_versions                = ch_versions.mix(FASTQ_ALIGN_STAR.out.versions)

    ch_multiqc_files = ch_multiqc_files
        .mix(FASTQ_ALIGN_STAR.out.stats.collect{it[1]})
        .mix(FASTQ_ALIGN_STAR.out.flagstat.collect{it[1]})
        .mix(FASTQ_ALIGN_STAR.out.idxstats.collect{it[1]})
        .mix(FASTQ_ALIGN_STAR.out.log_final.collect{it[1]})

    //
    // SUBWORKFLOW: Remove duplicate reads from BAM file based on UMIs
    //

    if (params.with_umi) {

        BAM_DEDUP_UMI(
            ch_genome_bam.join(ch_genome_bam_index, by: [0]),
            ch_fasta.map { [ [:], it ] },
            params.umi_dedup_tool,
            params.umitools_dedup_stats,
            params.bam_csi_index,
            ch_transcriptome_bam,
            ch_transcript_fasta.map { [ [:], it ] }
        )

        ch_genome_bam        = BAM_DEDUP_UMI.out.bam
        ch_transcriptome_bam = BAM_DEDUP_UMI.out.transcriptome_bam
        ch_genome_bam_index  = BAM_DEDUP_UMI.out.bai
        ch_versions          = ch_versions.mix(BAM_DEDUP_UMI.out.versions)

        ch_multiqc_files = ch_multiqc_files
            .mix(BAM_DEDUP_UMI.out.multiqc_files)
    }

    //
    // Take the riboseq samples and route to ribotish
    //

    ch_genome_bam
        .branch { meta, bam ->
            riboseq: meta.sample_type == 'riboseq'
                return [ meta, bam ]
            tiseq: meta.sample_type == 'tiseq'
                return [ meta, bam ]
            rnaseq: meta.sample_type == 'rnaseq'
                return [ meta, bam ]
        }
        .set{
            ch_genome_bam_by_type
        }

    ch_bams_for_analysis = ch_genome_bam_by_type.riboseq.join(ch_genome_bam_index)
    ch_fasta_gtf = ch_fasta.combine(ch_gtf).map{ fasta, gtf -> [ [:], fasta, gtf ] }.first()

    if (!params.skip_ribotish){
        RIBOTISH_QUALITY_RIBOSEQ(
            ch_bams_for_analysis,
            ch_gtf.map { [ [:], it ] }.first()
        )
        ch_versions      = ch_versions.mix(RIBOTISH_QUALITY_RIBOSEQ.out.versions)

        ribotish_predict_inputs = ch_bams_for_analysis
            .join(RIBOTISH_QUALITY_RIBOSEQ.out.offset)
            .multiMap{ meta, bam, bai, offset ->
                bam: [ meta, bam, bai ]
                offset: [ meta, offset ]
            }

        RIBOTISH_PREDICT_INDIVIDUAL(
            ribotish_predict_inputs.bam,
            [[:],[],[]],
            ch_fasta_gtf,
            [[:],[]],
            ribotish_predict_inputs.offset,
            [[:],[]]
        )
        ch_versions = ch_versions.mix(RIBOTISH_PREDICT_INDIVIDUAL.out.versions)

        RIBOTISH_PREDICT_ALL(
            ribotish_predict_inputs.bam.map{meta, bam, bai -> [[id:'allsamples'], bam, bai]}.groupTuple(),
            [[:],[],[]],
            ch_fasta_gtf,
            [[:],[]],
            ribotish_predict_inputs.offset.map{meta, offset -> [[id:'allsamples'], offset]}.groupTuple(),
            [[:],[]]
        )
        ch_versions = ch_versions.mix(RIBOTISH_PREDICT_ALL.out.versions)
    }

    if (!params.skip_ribotricer){
        RIBOTRICER_PREPAREORFS(
            ch_fasta_gtf
        )
        ch_versions = ch_versions.mix(RIBOTRICER_PREPAREORFS.out.versions)

        RIBOTRICER_DETECTORFS(
            ch_bams_for_analysis,
            RIBOTRICER_PREPAREORFS.out.candidate_orfs
        )
        ch_versions = ch_versions.mix(RIBOTRICER_DETECTORFS.out.versions)
    }

    //
    // SUBWORKFLOW: Count reads from BAM alignments using Salmon
    //

    QUANTIFY_STAR_SALMON (
        ch_samplesheet.map { [ [:], it ] },
        ch_transcriptome_bam,
        [],
        ch_transcript_fasta,
        ch_gtf,
        params.gtf_group_features,
        params.gtf_extra_attributes,
        'salmon',
        true,
        params.salmon_quant_libtype ?: '',
        null,
        null
    )
    ch_versions = ch_versions.mix(QUANTIFY_STAR_SALMON.out.versions)

    //
    // Do a translational efficiency analysis where contrasts are supplied
    //

    if (ch_contrasts_file){

        ch_contrasts = ch_contrasts_file
            .splitCsv ( header:true, sep:',' )
            .map{[it, it.variable, it.reference, it.target]}

        ch_samplesheet_matrix = QUANTIFY_STAR_SALMON.out.counts_gene_length_scaled
            .combine(ch_samplesheet)
            .map{[it[0], it[2], it[1]]}
            .first()

        ANOTA2SEQ_ANOTA2SEQRUN(
            ch_contrasts,
            ch_samplesheet_matrix
        )
        ch_versions = ch_versions.mix(ANOTA2SEQ_ANOTA2SEQRUN.out.versions)
    }

    //
    // Collate and save software versions
    //
    ch_versions = ch_versions.filter{it != null}

    softwareVersionsToYAML(ch_versions)
        .collectFile(storeDir: "${params.outdir}/pipeline_info", name: 'nf_core_pipeline_software_mqc_versions.yml', sort: true, newLine: true)
        .set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    if (!params.skip_multiqc) {
        ch_multiqc_config                     = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
        ch_multiqc_custom_config              = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
        ch_multiqc_logo                       = params.multiqc_logo ? Channel.fromPath(params.multiqc_logo, checkIfExists: true) : Channel.empty()
        summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
        ch_workflow_summary                   = Channel.value(paramsSummaryMultiqc(summary_params))
        ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
        ch_methods_description                = Channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_collated_versions)
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

        ch_name_replacements = ch_fastq
            .map{ meta, reads ->
                def name1 = file(reads[0][0]).simpleName + "\t" + meta.id + '_1'
                def fastqcnames = meta.id + "_raw\t" + meta.id + "\n" + meta.id + "_trimmed\t" + meta.id
                if (reads[0][1] ){
                    def name2 = file(reads[0][1]).simpleName + "\t" + meta.id + '_2'
                    def fastqcnames1 = meta.id + "_raw_1\t" + meta.id + "_1\n" + meta.id + "_trimmed_1\t" + meta.id + "_1"
                    def fastqcnames2 = meta.id + "_raw_2\t" + meta.id + "_2\n" + meta.id + "_trimmed_2\t" + meta.id + "_2"
                    return [ name1, name2, fastqcnames1, fastqcnames2 ]
                } else{
                    return [ name1, fastqcnames ]
                }
            }
            .flatten()
            .collectFile(name: 'name_replacement.txt', newLine: true)

        MULTIQC (
            ch_multiqc_files.collect(),
            ch_multiqc_config.toList(),
            ch_multiqc_custom_config.toList(),
            ch_multiqc_logo.toList(),
            ch_name_replacements,
            []
        )
    ch_multiqc_report = MULTIQC.out.report.toList()
    } else {
        ch_multiqc_report = Channel.empty()
    }

    emit:
    multiqc_report = ch_multiqc_report   // channel: /path/to/multiqc_report.html
    versions       = ch_versions         // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
