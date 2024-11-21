process PYDEFACE {
    tag "$meta.id"
    label 'process_low'

    conda "bioconda::pydeface=2.0.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://github.com/poldracklab/pydeface/releases/download/v2.0.0/pydeface-2.0.0.sif':
        'poldracklab/pydeface:2.0.0' }"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("*_defaced.nii.gz"), emit: defaced_image
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extension = input_file.extension ? input_file.extension : ''
    def filename = input_file.name.toString().minus(extension)
    """
    pydeface $input_file \\
        --outfile ${filename}_defaced${extension} \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: \$(pydeface --version 2>&1 | sed 's/pydeface, version //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extension = input_file.extension ? input_file.extension : ''
    def filename = input_file.name.toString().minus(extension)
    """
    touch ${filename}_defaced${extension}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: 2.0.0
    END_VERSIONS
    """
}