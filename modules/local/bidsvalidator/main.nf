process BIDSVALIDATOR {
    tag "$meta.id"
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://bids/validator:v1.15.0':
        'bids/validator:v1.15.0' }"

    input:
    tuple val(meta), path(input_dir)

    output:
    tuple val(meta), path("${prefix}_validation_log.txt"), emit: log
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    bids-validator \\
        $input_dir \\
        --verbose \\
        $args \\
        > ${prefix}_validation_log.txt 2>&1

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bids-validator: \$(bids-validator --version | sed 's/bids-validator v//g')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_validation_log.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bids-validator: 1.14.13
    END_VERSIONS
    """
}
