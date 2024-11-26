/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DCM2BIDS               } from '../modules/local/dcm2bids'
include { BIDSVALIDATOR          } from '../modules/local/bidsvalidator'
include { MRIQC                  } from '../modules/local/mriqc'
include { FMRIPREP               } from '../modules/local/fmriprep'
include { PYDEFACE               } from '../modules/local/pydeface'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_neuromriprep_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NEUROMRIPREP {

    take:
    ch_input_dirs // channel: [ val(meta), path(input_dir) ]
    ch_bids_dir   // channel: path(bids_dir)
    ch_config     // channel: path(config_file)
    ch_fs_license // channel: path(fs_license)

    main:

    ch_versions = Channel.empty()
    ch_input_dirs = Channel.fromPath(params.input_dirs, type: 'dir')
        .map { dir -> 
            def meta = [id: dir.name]
            [meta, dir]
        }
    ch_bids_dir = Channel.value(file(params.bids_dir))
    ch_config = Channel.fromPath(params.config)
    ch_fs_license = Channel.fromPath(params.fs_license)

    // Run workflow based on parameter input values
    if (params.run_dcm2bids) {
        DCM2BIDS(ch_input_dirs, ch_config)
        ch_versions = ch_versions.mix(DCM2BIDS.out.versions)
    }
    if (params.run_bidsvalidator) {
        BIDSVALIDATOR(ch_bids_dir)
        ch_versions = ch_versions.mix(BIDSVALIDATOR.out.versions)
    }
    if (params.run_pydeface) {
        ch_anat_files = Channel.fromPath("${params.bids_dir}/**/*.nii.gz")
            .filter { it.toString().contains("/anat/") }
            .map { file -> 
                def meta = [id: file.parent.name]
                [meta, file]
            }
        PYDEFACE(ch_anat_files)
        ch_versions = ch_versions.mix(PYDEFACE.out.versions)
    }
    if (params.run_mriqc) {
        MRIQC(ch_bids_dir)
        ch_versions = ch_versions.mix(MRIQC.out.versions)
    }
    if (params.run_fmriprep) {
        FMRIPREP(ch_bids_dir, ch_fs_license)
        ch_versions = ch_versions.mix(FMRIPREP.out.versions)
    }
    if (params.run_complete) {

        // Step 1: Convert DICOM to BIDS
        DCM2BIDS ( ch_input_dirs, ch_config )

        // Step 2: Validate BIDS data
        BIDSVALIDATOR ( ch_bids_dir )

        ch_anat_files = DCM2BIDS.out.bids_files
        .map { meta, files -> 
            def anat_files = files.findAll { it.toString().contains("/anat/") && it.name.endsWith(".nii.gz") }
            return [ meta, anat_files ]
        }
        .transpose()

        // Step 3: Deface anatomical images
        PYDEFACE(ch_anat_files)

        // Step 4: Run MRIQC
        MRIQC ( ch_bids_dir)

        // Step 5: Run fMRIPrep
        FMRIPREP ( ch_bids_dir, ch_fs_license )

        ch_versions = ch_versions.mix(DCM2BIDS.out.versions)
        ch_versions = ch_versions.mix(BIDSVALIDATOR.out.versions)
        ch_versions = ch_versions.mix(PYDEFACE.out.versions)
        ch_versions = ch_versions.mix(MRIQC.out.versions)
        ch_versions = ch_versions.mix(FMRIPREP.out.versions)
    }

    
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  + 'pipeline_software_' +  'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }
 

   emit:
    bids_files      = DCM2BIDS.out.bids_files
    defaced_images  = PYDEFACE.out.defaced_image
    mriqc_output    = MRIQC.out.mriqc_output
    fmriprep_output = FMRIPREP.out.fmriprep_output
    versions        = ch_versions.ifEmpty(null)

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
