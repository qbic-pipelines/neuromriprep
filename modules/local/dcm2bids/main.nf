// TODO nf-core: If in doubt look at other nf-core/modules to see how we are doing things! :)
//               https://github.com/nf-core/modules/tree/master/modules/nf-core/
//               You can also ask for help via your pull request or on the #modules channel on the nf-core Slack workspace:
//               https://nf-co.re/join
// TODO nf-core: A module file SHOULD only define input and output files as command-line parameters.
//               All other parameters MUST be provided using the "task.ext" directive, see here:
//               https://www.nextflow.io/docs/latest/process.html#ext
//               where "task.ext" is a string.
//               Any parameters that need to be evaluated in the context of a particular sample
//               e.g. single-end/paired-end data MUST also be defined and evaluated appropriately.
// TODO nf-core: Software that can be piped together SHOULD be added to separate module files
//               unless there is a run-time, storage advantage in implementing in this way
//               e.g. it's ok to have a single module for bwa to output BAM instead of SAM:
//                 bwa mem | samtools view -B -T ref.fasta
// TODO nf-core: Optional inputs are not currently supported by Nextflow. However, using an empty
//               list (`[]`) instead of a file can be used to work around this issue.

process DCM2BIDS {
    tag "$meta.id"
    label 'process_single'

    
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/YOUR-TOOL-HERE':
        'biocontainers/YOUR-TOOL-HERE' }"

    input:
    tuple val(meta), path(dicom_dir)
    path config_file
    
    output:
    tuple val(meta), path("bids_output/**") , emit: bids_files
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p bids_output

    apptainer run -e --containall \\
        -B ${dicom_dir}:/dicoms:ro \\
        -B ${config_file}:/config.json:ro \\
        -B ./bids_output:/bids \\
        --session ${meta.session_id} \\
        -o /bids \\
        -d /dicoms \\
        -c ${config_file} \\
        -p ${meta.id} \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: \$(dcm2bids --version 2>&1 | sed 's/dcm2bids //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p bids_output
    mkdir -p bids_output/sub-${meta.id}/ses-${meta.session_id}
    touch bids_output/sub-${meta.id}/ses-${meta.session_id}/sub-${meta.id}_ses-${meta.session_id}_T1w.nii.gz
    touch bids_output/sub-${meta.id}/ses-${meta.session_id}/sub-${meta.id}_ses-${meta.session_id}_T2w.nii.gz
    touch bids_output/dataset_description.json
    touch bids_output/participants.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: 2.1.9
    END_VERSIONS
    """
}
