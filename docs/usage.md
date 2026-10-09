# Technical setup and usage

## 1. Prepare the execution environment

Use a Linux machine or HPC environment with Nextflow >=25.04.0, a compatible Java installation, Apptainer on compute-node `PATH`, and access to the study's container images. The current workflow is adapted to local SIF images; it is not a Docker-only quick start. Obtain images and study configuration from your site maintainer. This repository does not provide portable builds of all custom images.

Check the installed tools:

```bash
java -version
nextflow -version
apptainer --version
```

Plan resources before a full run. The current overrides request 16 CPUs and 30 GB for the MRIQC participant task, and 16 CPUs and 60 GB per fMRIPrep task (up to three concurrent tasks). Other branches can run at the same time. Reduce concurrency to fit the host or scheduler; published results and task staging can occupy substantial space. No general disk or runtime estimate has been established.

The merge task uses GNU `cp --reflink=always`, without a fallback. The source and destination task files must support copy-on-write cloning on compatible storage. Check your chosen work filesystem with small disposable files before using imaging data:

```bash
mkdir -p /scratch/neuromriprep-work
printf 'reflink check\n' > /scratch/neuromriprep-work/reflink-source.txt
cp --reflink=always /scratch/neuromriprep-work/reflink-source.txt /scratch/neuromriprep-work/reflink-copy.txt
```

If this fails, use compatible storage or resolve the merge implementation with the maintainer before proceeding.

## 2. Clone the code

```bash
git clone --branch dev https://github.com/luiskuhn/neuromriprep.git
cd neuromriprep
git rev-parse HEAD
```

Record the commit, parameters, site configuration, and image checksums with your study. Run the following examples from the repository root because the ignore-list paths are resolved relative to the launch directory. Do not use `-profile test` or `test_full` as validation of an MRI installation: these are inherited template configurations.

## 3. Prepare the samplesheet and conversion mapping

Create `samplesheet.csv` (one row per DICOM participant/session directory):

```csv
project,dicom_dir
STUDY,/data/dicom/STUDY_001_S01
STUDY,/data/dicom/STUDY_002_S01
```

| Field       | Meaning                                                                                                                                        |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `project`   | Study label carried in metadata. Rows are merged into one dataset, not separated into project outputs.                                         |
| `dicom_dir` | Absolute path to an existing directory containing that acquisition's DICOM files. Use paths without whitespace for the current shell wrappers. |

The parser splits the **basename** on `_`: the second component is the subject; the third is searched for `S` followed by digits. `STUDY_001_S01` becomes `sub-001/ses-01`. Missing subject becomes `unknown`; missing/unrecognized session falls back to `01`. These fallbacks can silently mislabel data, so validate names before running. Do not prefix the subject component with `sub-`, and avoid underscores inside the study prefix. The two-component name `IRTG01_S01` is not equivalent: it would be parsed with subject `S01`.

Use a study-specific dcm2bids JSON file mapping your scanner series to BIDS datatypes, suffixes, entities, and field-map associations. A generic config cannot safely infer those choices. The workflow expects a `descriptions` array and modifies `B0FieldIdentifier`/`B0FieldSource` values containing `_fmap` with session suffixes. Review those edits and the study-specific postprocessing described in [pipeline architecture](pipeline.md) against your acquisition protocol.

Run a small representative participant/session first. For repeated sessions of one subject, resolve the [fMRIPrep duplicate-task limitation](pipeline.md#current-development-limitations) before launching full preprocessing.

## 4. Create required local policy files

These files are not shipped and their directory is Git-ignored. Create empty files for a new checkout, then add only study-reviewed exceptions (do not overwrite an existing study policy):

```bash
mkdir -p assets/input_pipeline
touch assets/input_pipeline/bidsignore_list.txt
touch assets/input_pipeline/bidsignore_remove.txt
touch assets/input_pipeline/bidsval_allowlist.txt
```

- `bidsignore_list.txt`: one BIDS ignore pattern per line to add to `.bidsignore`.
- `bidsignore_remove.txt`: one exact existing entry per line to remove.
- `bidsval_allowlist.txt`: one accepted validator warning code per line. An empty file accepts no warnings; errors cannot be allowlisted.

Ignoring a path prevents its validation; allowlisting a warning accepts a reported finding. Neither repairs the data. Inspect the validator log before adding exceptions.

For optional participant selection, use one subject label per line, such as `001` or `sub-001`. Use plain labels with no comments to work across all three selectors. MRIQC alone additionally supports comments and whitespace-separated labels. The historic `vpn` parameter name means a participant list, not a network VPN.

## 5. Configure images, resources, and reference data

Create `site.config`. The following illustrates the actual `task.ext.container` override mechanism. Replace every `/srv` path with an existing, suitable image or reference directory. The helper image must contain Bash, jq, and GNU coreutils, the validator image must contain Bash and `bids-validator`, and each scientific image must expose the executable used in its module.

```groovy
process {
    withName: 'DCM2BIDS_CONFIG|DCM2BIDS_POSTPROC|MERGE_BIDS_DATASET|BIDSIGNORE' {
        ext.container = '/srv/containers/docker-curl-jq.sif'
    }
    withName: 'DCM2BIDS|DCM2BIDS_OUTPUT_PATCH' {
        ext.container = '/srv/containers/dcm2bids_3.2.0.sif'
    }
    withName: 'BIDS_VALIDATOR' {
        ext.container = '/srv/containers/bidsvalidator_bash.sif'
    }
    withName: 'BIDS_QC_GATE' {
        ext.container = '/srv/containers/python_3.11.14-trixie.sif'
    }
    withName: 'FMRIPREP' {
        ext.container = '/srv/containers/fmriprep_24.1.1.sif'
        ext.templateflow_host = '/srv/templateflow'
        cpus = 16
        memory = '60 GB'
        maxForks = 1
    }
    withName: 'PYDEFACE' {
        ext.container = '/srv/containers/pydeface_3.0.sif'
        maxForks = 1
    }
    withName: 'MRIQC_PARTICIPANT' {
        cpus = 16
        memory = '30 GB'
    }
}
```

For a scheduler, additionally configure your site's executor, queue/account and storage mounts in this file. Without an executor override, tasks run locally. Verify absolute input, scratch, image, and reference paths are accessible on compute nodes.

Most declared `*_container` parameters in `nextflow.config` are **not wired into modules**; passing `--fmriprep_container`, for example, does not change `FMRIPREP`'s image. Use the process overrides above. MRIQC is an exception: its participant wrapper calls `apptainer run` using `--mriqc_container`, while its group wrapper hard-codes `/nic/sw/IRTG/sif/mriqc_25.0.0rc0.sif`. Your site must make that group image available at that path, or the wrapper must be changed before running MRIQC elsewhere. A process container override does not replace that embedded command argument.

fMRIPrep requires a valid FreeSurfer license and a populated TemplateFlow cache accessible at `ext.templateflow_host` (bound to `/templateflow`). Obtain the license through FreeSurfer and prepare the references required by the selected output spaces. The default license and TemplateFlow paths are institutional. `ses01`/`ses02` filter aliases also resolve to institutional paths: provide your own JSON filter instead.

### Container preparation and checks

The prototype’s image-building notes are useful for setup, but its full image set is historical. For dcm2bids, the current default still uses 3.2.0; its [versioned upstream documentation](https://unfmontreal.github.io/Dcm2Bids/3.2.0/how-to/container/) provides this pull pattern:

```bash
mkdir -p /data/study/containers
apptainer pull /data/study/containers/dcm2bids_3.2.0.sif docker://unfmontreal/dcm2bids:3.2.0
apptainer exec /data/study/containers/dcm2bids_3.2.0.sif dcm2bids --help
```

Set the corresponding `ext.container` path in `site.config`. This prepares the conversion image only; helper, QC, preprocessing, and defacing images still need separate configuration.

The current validator executes a Bash task script and calls `bids-validator` directly. Do not assume the prototype’s `validator_1.14.13.sif` is interchangeable with `bidsvalidator_bash.sif`. Check a candidate image before using it:

```bash
apptainer exec /srv/containers/bidsvalidator_bash.sif bash -c 'command -v bids-validator && bids-validator --version'
```

Also inspect a representative validation log: [bids_gate.py](../assets/scripts/bids_gate.py) recognizes textual `[ERROR] CODE` and `[WARNING] CODE` entries. A version check alone does not verify compatibility with that parser. Record image checksums and actual tool versions; the MRIQC wrappers currently write a fixed version string, and SIF filenames are not authoritative version records. These examples were checked against documentation/source, not executed with containers here.

## 6. Create a parameter file

Create `bids_filter.json` containing `{}` for an unrestricted filter, or supply a study-reviewed fMRIPrep BIDS filter. The repository's default `assets/empty_bids_filter.json` is absent, so an explicit file is required.

Create `params.yaml`, replacing all example paths:

```yaml
mode: production
input: /data/study/samplesheet.csv
outdir: /data/study/results
dcm2bids_config: /data/study/dcm2bids_config.json
bids_qc_allowlist: assets/input_pipeline/bidsval_allowlist.txt
enforce_bidsqc_gate: true
stop_bidsval: true
stop_mriqc: true
stop_fmriprep: true
skip_mriqc: false
skip_fmriprep: false
mriqc_vpn_file: null
fmriprep_vpn_file: null
pydeface_vpn_file: null
mriqc_container: /srv/containers/mriqc_25.0.0rc0.sif
fmriprep_fs_license: /data/study/license.txt
fmriprep_bids_filter: /data/study/bids_filter.json
ignore_fmriprep_fail: false
deface_tool: pydeface
```

Null participant lists select all available participants for that branch. They also override missing repository defaults. The FreeSurfer license and filter are needed when fMRIPrep is enabled. The default defacer is `pydeface`; other production choices are `mri_deface`, `fsl_deface`, and `afni_refacer`, each requiring its own process image override. `mri_deface` additionally requires its brain/face template files inside the image or an accessible bind mount.

Use `-params-file` or `--parameter value` for pipeline parameters and `-c` for process/executor configuration. Nextflow options use a single hyphen. Do not treat the old sequencing schema as a current parameter reference.

## 7. Validate configuration and run in stages

```bash
nextflow config . -profile apptainer -c site.config -flat > resolved.config.txt
```

Inspect resolved process overrides. This checks configuration resolution, not availability of images, correctness of input data, or success of the pipeline. Follow the [production workflow guide](production_workflow_guide.md) for the actual commands and review checkpoints.

## Standalone application diagnostics

The [integrated container guide](prototype-notes.md#standalone-container-guide-retained-from-the-prototype) includes the precursor’s applicable technical instructions directly in this repository: image preparation, DICOM layout, conversion, validation and field-map repair, individual/project MRIQC, participant-level fMRIPrep, and PyDeface execution. Commands are adapted to the current code and use separate scratch outputs. Use them to diagnose an application; use the staged Nextflow guide for production orchestration.

## Operational parameter reference

| Parameter                                                  | Default / effect                                                                                                                        |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `mode`                                                     | `production` or `benchmark_defacing`.                                                                                                   |
| `input`, `dcm2bids_config`, `outdir`                       | Provide explicit study paths; repository defaults are not usable study examples.                                                        |
| `stop_bidsval`, `stop_mriqc`, `stop_fmriprep`              | All default to `true`; see the checkpoint truth table.                                                                                  |
| `skip_mriqc`, `skip_fmriprep`                              | Default `false`; skipping can bypass a stop condition.                                                                                  |
| `enforce_bidsqc_gate`                                      | Default `true`; false reports the gate but lets production branches proceed.                                                            |
| `bids_qc_allowlist`, `bids_qc_helpers`                     | Warning policy and optional helper text for the gate.                                                                                   |
| `force_dcm2bids`                                           | Default `false`; enables the converter's force option, not a global Nextflow cache reset.                                               |
| `dcm2bids_output_patch_vpn`                                | Optional production-only participant list activating the predefined field-map patch; inspect `bin/dcm2bids_output_patch.py` before use. |
| `mriqc_vpn_file`, `fmriprep_vpn_file`, `pydeface_vpn_file` | Separate branch participant selectors; do not restrict initial conversion.                                                              |
| `fmriprep_bids_filter`, `fmriprep_fs_license`              | Explicit filter JSON and license paths.                                                                                                 |
| `ignore_fmriprep_fail`                                     | Default `true` retries once then ignores failures; use `false` to terminate on failure.                                                 |
| `deface_tool`                                              | Production defacer; does not select benchmark methods.                                                                                  |

## Troubleshooting and reproducibility

| Symptom                                               | Check / action                                                                                                 |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Missing `assets/input_pipeline` file                  | Create the required policies and explicitly set participant list paths or nulls.                               |
| Missing SIF or `apptainer: command not found`         | Verify compute-node paths and runtime; MRIQC group has a fixed SIF path.                                       |
| `cp` reports reflink unsupported                      | Move the work directory to compatible storage; the merge has no ordinary-copy fallback.                        |
| No downstream tasks despite successful exit           | Inspect `bids_qc_summary.txt`, validator log, stop/skip flags, and selection lists.                            |
| Missing fMRIPrep filter/license/templates             | Supply explicit paths; do not use institutional aliases on another site.                                       |
| Missing participant outputs                           | Check `.nextflow.log`, trace and task logs; ignored fMRIPrep failures can leave incomplete results.            |
| No defaced images                                     | Confirm the parsed subject/session and `anat/*.nii.gz` exist, the selector matches, and the branch is enabled. |
| Duplicate fMRIPrep jobs or overwritten configurations | See the multi-session and publication limitations in [pipeline architecture](pipeline.md).                     |

### Validation and field-map troubleshooting

Retained from the [prototype guide](prototype-notes.md), with current gate behavior:

| Finding                                              | Investigate before changing the dataset                                                                                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BOLD_NOT_4D` or `NIFTI_PIXDIM4`                     | Compare acquisition records, source-series completeness, conversion logs, and NIfTI dimensions/time spacing. An interrupted acquisition is one possibility; do not automatically delete the scan.                                    |
| Inconsistent subjects/parameters or missing sessions | Compare against the study design, samplesheet names, and conversion mapping. Decide whether data are missing or variation is expected before allowlisting the actual warning code.                                                   |
| Non-BIDS logs or temporary files                     | Inspect the reported path and the effective lowercase `.bidsignore`. The current postprocessor already handles ADC files, DWI SBRef gradients, and temporary conversion files. Avoid importing the prototype’s exclusions wholesale. |
| Field-map references after excluding/remapping a run | Check `IntendedFor` targets and consistency of `B0FieldIdentifier`/`B0FieldSource`. Correct the conversion configuration and validate the regenerated dataset before resuming fMRIPrep.                                              |

Validate the **dataset root**, not only a `sub-*` directory. Issue names/severity can vary with validator versions; use the actual log rather than historical numeric codes. See the [source-backed implementation checks](prototype-notes.md#current-implementation-checks).

Keep `.nextflow/` and the work directory until review is complete. Resume from the same launch directory with the same work directory; changed inputs or task definitions may invalidate caches. Do not edit published results expecting resumed upstream tasks to consume those edits: correct the source data/configuration and rerun. Archive parameters, configuration, commit, container identities and reports alongside the outputs. See [output documentation](output.md) for enabling execution reports and locating unpublished logs.
