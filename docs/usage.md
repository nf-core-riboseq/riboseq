# nf-core/riboseq: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/riboseq/usage](https://nf-co.re/riboseq/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Pipeline parameters

Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration except for parameters; see [docs](https://nf-co.re/usage/configuration#custom-configuration-files).

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Use this parameter to specify its location. It has to be a comma-separated file with 5 columns, and a header row as shown in the examples below.

```bash
--input '[path to samplesheet file]'
```

### Multiple runs of the same sample

The `sample` identifiers have to be the same when you have re-sequenced the same sample more than once e.g. to increase sequencing depth. The pipeline will concatenate the raw reads before performing any downstream analysis. Below is an example for the same sample sequenced across 3 lanes. If you set the strandedness value to `auto` the pipeline will sub-sample the input FastQ files to 1 million reads, use Salmon Quant to infer the strandedness automatically and then propagate this information to the remainder of the pipeline. If the strandedness has been inferred or provided incorrectly a warning will be present at the top of the MultiQC report so please be sure to check when looking at the QC for your samples.

```csv title="samplesheet.csv"
sample,fastq_1,fastq_2,strandedness,type
CONTROL_REP1,AEG588A1_S1_L002_R1_001.fastq.gz,AEG588A1_S1_L002_R2_001.fastq.gz,auto,riboseq
CONTROL_REP1,AEG588A1_S1_L003_R1_001.fastq.gz,AEG588A1_S1_L003_R2_001.fastq.gz,auto,riboseq
CONTROL_REP1,AEG588A1_S1_L004_R1_001.fastq.gz,AEG588A1_S1_L004_R2_001.fastq.gz,auto,riboseq
```

### Linting

By default, the pipeline will run [fq lint](https://github.com/stjude-rust-labs/fq) on all input FASTQ files, both at the start of preprocessing and after each preprocessing step that manipulates FASTQ files. If errors are found, and error will be reported and the workflow will stop.

The `extra_fqlint_args` parameter can be manipulated to disable [any validator](https://github.com/stjude-rust-labs/fq?tab=readme-ov-file#validators) from `fq` you wish. For example, we have found that checks on the names of paired reads are prone to failure, so that check is disabled by default (setting `extra_fqlint_args` to `--disable-validator P001`).

### Strandedness Prediction

If you set the strandedness value to `auto`, the pipeline will sub-sample the input FastQ files to 1 million reads, use Salmon Quant to automatically infer the strandedness, and then propagate this information through the rest of the pipeline. This behavior is controlled by the `--stranded_threshold` and `--unstranded_threshold` parameters, which are set to 0.8 and 0.1 by default, respectively. This means:

- **Forward stranded:** At least 80% of the fragments are in the 'forward' orientation.
- **Unstranded:** The forward and reverse fractions differ by less than 10%.
- **Undetermined:** Samples that do not meet either criterion, possibly indicating issues such as genomic DNA contamination.

**Note:** These thresholds apply to both the strandedness inferred from Salmon outputs for input to the pipeline and how strandedness is inferred from RSeQC results using pipeline outputs.

#### Usage Examples

1. **Forward Stranded Sample:**

   - Forward fraction: 0.85
   - Reverse fraction: 0.15
   - **Classification:** Forward stranded

2. **Reverse Stranded Sample:**

   - Forward fraction: 0.1
   - Reverse fraction: 0.9
   - **Classification:** Reverse stranded

3. **Unstranded Sample:**

   - Forward fraction: 0.45
   - Reverse fraction: 0.55
   - **Classification:** Unstranded

4. **Undetermined Sample:**
   - Forward fraction: 0.6
   - Reverse fraction: 0.4
   - **Classification:** Undetermined

You can control the stringency of this behavior with `--stranded_threshold` and `--unstranded_threshold`.

#### Errors and Reporting

The results of strandedness inference are displayed in the MultiQC report under 'Strandedness Checks'. This shows any provided strandedness and the results inferred by both Salmon (when strandedness is set to 'auto') and RSeQC. Mismatches between input strandedness (explicitly provided by the user or inferred by Salmon) and output strandedness from RSeQC are marked as fails. For example, if a user specifies 'forward' as strandedness for a library that is actually reverse stranded, this is marked as a fail.

![MultiQC - Strand check table](images/mqc_strand_check.png)

Be sure to check the strandedness report when reviewing the QC for your samples.

### Full samplesheet

The pipeline will auto-detect whether a sample is single- or paired-end using the information provided in the samplesheet. The samplesheet can have as many columns as you desire, however, there is a strict requirement for the first 5 columns to match those defined in the table below.

A final samplesheet file consisting of both single-end Ribo-seq samples and paired-end RNA-seq data may look something like the one below.

```csv title="samplesheet.csv"
sample,fastq_1,fastq_2,strandedness,type,sample_description,pair,treatment
SRX11780879,SRX11780879_SRR15480782_chr20_1.fastq.gz,SRX11780879_SRR15480782_chr20_2.fastq.gz,auto,rnaseq,PM2_5_0_1,1,control
SRX11780880,SRX11780880_SRR15480783_chr20_1.fastq.gz,SRX11780880_SRR15480783_chr20_2.fastq.gz,auto,rnaseq,PM2_5_0_2,2,control
SRX11780881,SRX11780881_SRR15480784_chr20_1.fastq.gz,SRX11780881_SRR15480784_chr20_2.fastq.gz,auto,rnaseq,PM2_5_0_3,3,control
SRX11780882,SRX11780882_SRR15480785_chr20_1.fastq.gz,SRX11780882_SRR15480785_chr20_2.fastq.gz,auto,rnaseq,PM2_5_400_1,4,treated
SRX11780883,SRX11780883_SRR15480786_chr20_1.fastq.gz,SRX11780883_SRR15480786_chr20_2.fastq.gz,auto,rnaseq,PM2_5_400_2,5,treated
SRX11780884,SRX11780884_SRR15480787_chr20_1.fastq.gz,SRX11780884_SRR15480787_chr20_2.fastq.gz,auto,rnaseq,PM2_5_400_3,6,treated
SRX11780885,SRX11780885_SRR15480788_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_C01,1,control
SRX11780886,SRX11780886_SRR15480789_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_C02,2,control
SRX11780887,SRX11780887_SRR15480790_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_C03,3,control
SRX11780888,SRX11780888_SRR15480791_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_P4001,4,treated
SRX11780889,SRX11780889_SRR15480792_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_P4002,5,treated
SRX11780890,SRX11780890_SRR15480793_chr20_1.fastq.gz,,auto,riboseq,Ribo-seq_P4003,6,treated
```

| Column         | Description                                                                                                                                                                            |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sample`       | Custom sample name. This entry will be identical for multiple sequencing libraries/runs from the same sample. Spaces in sample names are automatically converted to underscores (`_`). |
| `fastq_1`      | Full path to FastQ file for Illumina short reads 1. File has to be gzipped and have the extension ".fastq.gz" or ".fq.gz".                                                             |
| `fastq_2`      | Full path to FastQ file for Illumina short reads 2. File has to be gzipped and have the extension ".fastq.gz" or ".fq.gz".                                                             |
| `strandedness` | Sample strand-specificity. Must be one of `unstranded`, `forward`, `reverse` or `auto`.                                                                                                |
| `type`         | Type of sample. Must be one of `riboseq`, `rnaseq` or `tiseq`                                                                                                                          |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

When specifying `contrasts` to perform a translational efficiency analysis (see below), the `type` column is necessary to distinguish Ribo-seq and RNA-seq samples. There must further be a column somewhere in the table that separates the treatment groups to be compared (`treatment` in the above example). Optionally sample pairing can be specified via an additional column (`pair` in the example), by default the same ordering will be assumed between RNA-seq and Riboseq samples of the respective groups.

## Adapter trimming options

[Trim Galore!](https://www.bioinformatics.babraham.ac.uk/projects/trim_galore/) is a wrapper tool around Cutadapt and FastQC to peform quality and adapter trimming on FastQ files. Trim Galore! will automatically detect and trim the appropriate adapter sequence. It is the default trimming tool used by this pipeline, however you can use fastp instead by specifying the `--trimmer fastp` parameter. [fastp](https://github.com/OpenGene/fastp) is a tool designed to provide fast, all-in-one preprocessing for FastQ files. It has been developed in C++ with multithreading support to achieve higher performance. You can specify additional options for Trim Galore! and fastp via the `--extra_trimgalore_args` and `--extra_fastp_args` parameters, respectively.

> **NB:** TrimGalore! will only run using multiple cores if you are able to use more than > 5 and > 6 CPUs for single- and paired-end data, respectively. The total cores available to TrimGalore! will also be capped at 4 (7 and 8 CPUs in total for single- and paired-end data, respectively) because there is no longer a run-time benefit. See [release notes](https://github.com/FelixKrueger/TrimGalore/blob/master/Changelog.md#version-060-release-on-1-mar-2019) and [discussion whilst adding this logic to the nf-core/atacseq pipeline](https://github.com/nf-core/atacseq/pull/65).

## Alignment options

The pipeline currently uses [STAR](https://github.com/alexdobin/STAR) to map the raw FastQ reads to the reference genome and project the alignments onto the transcriptome. STAR is fast but requires a lot of memory to run, typically around 38GB for the Human GRCh37 reference genome.

### Unique Molecular Identifiers (UMIs)

The pipeline supports UMIs to increase the accuracy of the quantification. UMIs are short sequences used to uniquely tag each molecule in a sample library and facilitate the accurate identification of read duplicates. They must be added during library preparation and prior to sequencing, therefore require appropriate arrangements with your sequencing provider.

To take UMIs into consideration during a workflow run, specify the `--with_umi` parameter. The pipeline currently supports UMIs, which are embedded within a read's sequence and UMIs, whose sequence is given inside the read's name. Please consult your kit's manual and/or contact your sequencing provider regarding the exact specification.

The `--umitools_grouping_method` parameter affects [how similar, but non-identical UMIs](https://umi-tools.readthedocs.io/en/latest/reference/dedup.html#method) are treated. `directional`, the default setting, is most accurate, but computationally very demanding. Consider `percentile` or `unique` if processing many samples.

#### Examples:

| UMI type     | Source                                                                                                                                                                                                                                               | Pipeline parameters                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| In read name | [Illumina BCL convert >3.7.5](https://emea.support.illumina.com/content/dam/illumina-support/documents/documentation/software_documentation/bcl_convert/bcl-convert-v3-7-5-software-guide-1000000163594-00.pdf)                                      | `--with_umi --skip_umi_extract --umitools_umi_separator ":"`                                                                                   |
| In sequence  | [Lexogen QuantSeq® 3’ mRNA-Seq V2 FWD](https://www.lexogen.com/quantseq-3mrna-sequencing) + [UMI Second Strand Synthesis Module](https://faqs.lexogen.com/faq/how-can-i-add-umis-to-my-quantseq-libraries)                                          | `--with_umi --umitools_extract_method "regex" --umitools_bc_pattern "^(?P<umi_1>.{6})(?P<discard_1>.{4}).*"`                                   |
| In sequence  | [Lexogen CORALL® Total RNA-Seq V1](https://www.lexogen.com/corall-total-rna-seq/)<br> > _mind [Appendix H](https://www.lexogen.com/wp-content/uploads/2020/04/095UG190V0130_CORALL-Total-RNA-Seq_2020-03-31.pdf) regarding optional trimming_       | `--with_umi --umitools_extract_method "regex" --umitools_bc_pattern "^(?P<umi_1>.{12}).*"`<br>Optional: `--clip_r2 9 --three_prime_clip_r2 12` |
| In sequence  | [Takara Bio SMARTer® Stranded Total RNA-Seq Kit v3](https://www.takarabio.com/documents/User%20Manual/SMARTer%20Stranded%20Total%20RNA/SMARTer%20Stranded%20Total%20RNA-Seq%20Kit%20v3%20-%20Pico%20Input%20Mammalian%20User%20Manual-a_114949.pdf) | `--with_umi --umitools_extract_method "regex" --umitools_bc_pattern2 "^(?P<umi_1>.{8})(?P<discard_1>.{6}).*"`                                  |

> _No warranty for the accuracy or completeness of the parameters is implied_

## Reference genome options

Please refer to the [nf-core website](https://nf-co.re/usage/reference_genomes) for general usage docs and guidelines regarding reference genomes.

### Explicit reference file specification (recommended)

The minimum reference genome requirements for this pipeline are a FASTA and GTF file, all other files required to run the pipeline can be generated from these files. For example, the latest reference files for human can be derived from Ensembl like:

```
latest_release=$(curl -s 'http://rest.ensembl.org/info/software?content-type=application/json' | grep -o '"release":[0-9]*' | cut -d: -f2)
wget -L ftp://ftp.ensembl.org/pub/release-${latest_release}/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna_sm.primary_assembly.fa.gz
wget -L ftp://ftp.ensembl.org/pub/release-${latest_release}/gtf/homo_sapiens/Homo_sapiens.GRCh38.${latest_release}.gtf.gz
```

These files can then be specified to the workflow with the `--fasta` and `--gtf` parameters.

Notes:

- Compressed reference files are supported by the pipeline i.e. standard files with the `.gz` extension and indices folders with the `tar.gz` extension.

- If `--gff` is provided as input then this will be converted to a GTF file, or the latter will be used if both are provided.
- If `--gene_bed` is not provided then it will be generated from the GTF file.
- If `--additional_fasta` is provided then the features in this file (e.g. ERCC spike-ins) will be automatically concatenated onto both the reference FASTA file as well as the GTF annotation before building the appropriate indices.

#### Indices

By default, indices are generated dynamically by the workflow for tools such as STAR and Salmon. Since indexing is an expensive process in time and resources you should ensure that it is only done once, by retaining the indices generated from each batch of reference files:

- the `--save_reference` parameter will save your indices in your results directory
- the `--skip_alignment --skip_pseudo_alignment` will disable other processes if you'd like to do an 'indexing only' workflow run.

Once you have the indices from a workflow run you should save them somewhere central and reuse them in subsequent runs using custom config files or command line parameters such as `--star_index '/path/to/STAR/index/'`.

#### Gencode

If you are using [GENCODE](https://www.gencodegenes.org/) reference genome files please specify the `--gencode` parameter because the format of these files is slightly different to ENSEMBL genome files:

- The `--gtf_group_features_type` parameter will automatically be set to `gene_type` as opposed to `gene_biotype`, respectively.
- If you are running Salmon, the `--gencode` flag will also be passed to the index building step to overcome parsing issues resulting from the transcript IDs in GENCODE fasta files being separated by vertical pipes (`|`) instead of spaces (see [this issue](https://github.com/COMBINE-lab/salmon/issues/15)).

### iGenomes (not recommended)

If the `--genome` parameter is provided (e.g. `--genome GRCh37`) then the FASTA and GTF files (and existing indices) will be automatically obtained from AWS-iGenomes unless these have already been downloaded locally in the path specified by `--igenomes_base`.

However this is no longer recommended because:

- Gene annotations in iGenomes are extremely out of date. This can be particularly problematic for RNA-seq analysis, which relies on accurate gene annotation.
- Some iGenomes references (e.g., GRCh38) point to annotation files that use gene symbols as the primary identifier. This can cause issues for downstream analysis, such as the nf-core [differential abundance](https://nf-co.re/differentialabundance) workflow where a conventional gene identifier distinct from symbol is expected.

### GTF filtering

By default, the input GTF file will be filtered to ensure that sequence names correspond to those in the genome fasta file, and to remove rows with empty transcript identifiers. Filtering can be bypassed completely where you are confident it is not necessary, using the `--skip_gtf_filter` parameter. If you just want to skip the 'transcript_id' checking component of the GTF filtering script used in the pipeline this can be disabled specifically using the `--skip_gtf_transcript_filter` parameter.

## Riboseq-specific options

The pipeline will by default run the [Ribo-TISH](https://github.com/zhpn1024/ribotish) [quality](https://github.com/zhpn1024/ribotish?tab=readme-ov-file#quality) and [predict](https://github.com/zhpn1024/ribotish?tab=readme-ov-file#predict) commands for QC and ORF prediction, respectively. Additional arguments can be supplied to either command via the `--extra_ribotish_quality_args` and `--extra_ribotish_predict_args` parameters.

## Translational efficiency

If you have paired RNA-seq and Riboseq samples, you can use this workflow to initiate a translational efficiency analysis.

Translational efficiency analysis as conducted by [anota2seq](https://bioconductor.org/packages/release/bioc/html/anota2seq.html) involves the integrated analysis of RNA-seq and Ribo-seq data to discern changes in translational efficiency across different experimental conditions. It quantitatively assesses how variations in mRNA abundance and ribosome occupancy lead to alterations in protein synthesis, enabling the identification of genes with post-transcriptional and translational regulation.

anota2seq studies differences between conditions for both RNA-seq and Ribo-seq samples. It also assesses combined results from two measures as they relate to one another:

- Differences in translation (Riboseq abundance values) driven by changes in overall RNA-seq abundance values
- Differences in translation not occuring as a result of overall RNA levels
- Changes in total RNA levels that do not lead to increased translation ('buffering'):

This table may help:

| Aspect      | RNAseq    | Riboseq   |
| ----------- | --------- | --------- |
| Abundance   | Changed   | Changed   |
| Translation | Unchanged | Changed   |
| Buffering   | Changed   | Unchanged |

To carry out this analysis, the pipeline must be supplied with one or more 'contrasts' describing the comparison to be made.

For example the test data for this workflow has a contrasts file like:

```csv
id,variable,reference,target,batch,pair
treated_vs_control,treatment,control,treated,,pair
```

This describes how to compare groups of samples between treament groups, and between RNA-seq and Ribo-seq. In order the columns are:

- `id`: a unique identifier to use for the contrast
- 'variable`: which vaiable (column) of the sample sheet should be used to separate the treatment groups?
- `reference`: which value of the variable column should be used to select samples to be used as the reference/ base group?
- `target`: which value of the variable column should be used to select samples to be used as the target/treated group?
- `batch`: (optional) specify a variable in the sample sheet that defines sample batches
- `pair`: (optional) specify a variable in the sample shet that defines sample pairing between RNA-seq and Ribo-seq samples. If not specified, it is assumed that the two types of sample are ordered the same.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run \
    nf-core/riboseq \
    --input <SAMPLESHEET> \
    --outdir <OUTDIR> \
    --gtf <GTF> \
    --fasta <GENOME FASTA> \
    -profile docker
```

> **NB:** Loading iGenomes configuration remains the default for reasons of consistency with other workflows, but should be disabled when not using iGenomes, applying the recommended usage above.

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/riboseq -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: './samplesheet.csv'
outdir: './results/'
genome: 'GRCh37'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/riboseq
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/riboseq releases page](https://github.com/nf-core/riboseq/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://hpc.github.io/charliecloud/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/usage/configuration#max-resources) and [tuning workflow resources](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/usage/configuration#updating-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
