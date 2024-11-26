process MRIQC {
    tag "$meta.id"
    label 'process_medium'

    conda "bioconda::mriqc=24.0.2"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://github.com/nipreps/mriqc/releases/download/24.0.2/mriqc-24.0.2.sif':
        'nipreps/mriqc:24.0.2' }"

    input:
    tuple val(meta), path(input_dir)
    

    output:
    tuple val(meta), path("results/*")    , emit: mriqc_output
    path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mem_gb = task.memory.toGiga()
    """

    mkdir -p \$PWD/results
    results="\$PWD/results"

    mriqc \\
        $input_dir \\
        \$results \\
        participant \\
        --participant-label $prefix \\
        --nprocs $task.cpus \\
        --omp-nthreads $task.cpus \\
        --mem_gb $mem_gb \\
        --no-sub \\
        -vvv \\
        --verbose-reports \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mriqc: \$(mriqc --version 2>&1 | sed 's/mriqc, version //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p ${output_dir}/sub-${prefix}
    touch ${output_dir}/sub-${prefix}/sub-${prefix}_T1w.html
    touch ${output_dir}/sub-${prefix}/sub-${prefix}_T1w.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mriqc: 24.0.2
    END_VERSIONS
    """
}