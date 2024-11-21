process FMRIPREP {
    tag "$meta.id"
    label 'process_high'
    label 'process_long'

    conda "bioconda::fmriprep=24.0.1"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://github.com/nipreps/fmriprep/releases/download/24.0.1/fmriprep-24.0.1.sif':
        'nipreps/fmriprep:24.0.1' }"

    input:
    tuple val(meta), path(input_dir)
    path output_dir
    path fs_license

    output:
    tuple val(meta), path("${output_dir}"), emit: fmriprep_output
    path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def random_seed = task.ext.random_seed ?: 13
    """
    fmriprep \\
        $input_dir \\
        $output_dir \\
        participant \\
        --participant-label $prefix \\
        --fs-license-file $fs_license \\
        --skip_bids_validation \\
        --omp-nthreads $task.cpus \\
        --random-seed $random_seed \\
        --skull-strip-fixed-seed \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fmriprep: \$(fmriprep --version 2>&1 | sed 's/fmriprep v//g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p ${output_dir}/sub-${prefix}
    touch ${output_dir}/sub-${prefix}/sub-${prefix}_desc-preproc_T1w.nii.gz
    touch ${output_dir}/sub-${prefix}/sub-${prefix}_desc-preproc_bold.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fmriprep: 24.0.1
    END_VERSIONS
    """
}