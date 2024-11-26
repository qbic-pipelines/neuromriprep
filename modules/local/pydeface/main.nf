process PYDEFACE {
    tag "$meta.id"
    label 'process_low'


    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://poldracklab/pydeface:37-2e0c2d':
        'poldracklab/pydeface:37-2e0c2d' }"

    input:
    tuple val(meta), path(input_file, stageAs: "input.nii.gz")

    output:
    tuple val(meta), path("*_defaced.nii.gz"), emit: defaced_image
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    //def extension = input_file.extension ? input_file.extension : ''
    //def filename = input_file.name.toString().minus(extension)
    """
    pydeface input.nii.gz \\
        --outfile ${prefix}_defaced.nii.gz \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: \$(pydeface --version 2>&1 | sed 's/pydeface, version //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_defaced.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: 2.0.0
    END_VERSIONS
    """
}
