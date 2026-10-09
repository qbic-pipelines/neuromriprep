# Lessons retained from the prototype

The [IRTG MRI ImagePreprocessing usage guide](https://github.com/luiskuhn/IRTG_MRI_ImagePreprocessing/blob/7cb194818a6905494a9b28b57cb0f9a02817f4f2/docs/usage.md) documents the precursor project (reviewed at commit `7cb1948`). Its acquisition troubleshooting remains useful, but its commands, image versions, and output paths are not the current pipeline interface. The retained guidance below was checked against the current `dev` branch at [commit `a67c552`](https://github.com/luiskuhn/neuromriprep/tree/a67c5526922e89ee3c62246129fd2ea1120179d3).

## Useful operational guidance

- **Diagnose acquisition problems before excluding images.** The prototype associates `BOLD_NOT_4D` and `NIFTI_PIXDIM4` findings with potentially incomplete series. Treat these as investigation leads: compare source acquisitions, conversion logs, and image dimensions. They do not establish a diagnosis or justify automatic deletion.
- **Reconcile missing data with the study protocol.** For inconsistent subjects/parameters or missing sessions, check expected acquisitions against converted outputs before accepting a warning. Current production blocks non-allowlisted warnings; see [validation troubleshooting](usage.md#validation-and-field-map-troubleshooting).
- **Maintain field-map associations when the acquisition set changes.** Review `IntendedFor` and the current `B0FieldIdentifier`/`B0FieldSource` associations after excluding or remapping runs. The optional patch in [bin/dcm2bids_output_patch.py](../bin/dcm2bids_output_patch.py) is study-specific: its field identifiers contain session 01 and its GRE mapping assumes run-01/rest and run-02/EAT. It is not a general field-map repair tool.
- **Check container contents, not just filenames.** Retain the prototype’s pinned-image approach, but use current module requirements. The [container preparation notes](usage.md#container-preparation-and-checks) include a verified dcm2bids pull command and validator compatibility checks.
- **Keep a readable BIDS layout.** The [output example](output.md#example-converted-dataset) explains anatomical, functional, field-map, and diffusion files without promising files this implementation does not publish.

## Current implementation checks

| Operational rule                                                                                                              | Current code reference                                                                                                                                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Validate the merged dataset root, including `dataset_description.json`; use lowercase `.bidsignore`.                          | [BIDS_VALIDATOR](../modules/local/bidsvalidator/main.nf) receives the dataset after ignore processing.                                                                                                              |
| Review every error and non-allowlisted warning before continuing.                                                             | [BIDS_QC_GATE](../modules/local/bidsqcgate/main.nf) and [bids_gate.py](../assets/scripts/bids_gate.py) determine pass/fail from the validator log.                                                                  |
| Inspect remaining validation findings before adding ADC, SBRef, or temporary-file exclusions.                                 | [DCM2BIDS_POSTPROC](../modules/local/dcm2bidspostprocess/main.nf) already handles these outputs.                                                                                                                    |
| Use explicit participant selection and a reviewed BIDS filter for fMRIPrep.                                                   | [FMRIPREP_PARTICIPANTS](../subworkflows/local/fmriprep_participants/main.nf) stages the merged dataset; its [duplicate participant-task limitation](pipeline.md#current-development-limitations) still applies.     |
| Keep filenames and field-map references consistent after reviewed exclusions; do not automatically strip run indices.         | The conversion configuration determines names; the [BIDS run entity](https://bids-specification.readthedocs.io/en/v1.9.0/appendices/entities.html#run) does not require removing an existing index after exclusion. |
| Prepare a TemplateFlow cache accessible inside the container and use your site's proxy/trusted CA configuration where needed. | [FMRIPREP](../modules/local/fmriprep/main.nf) uses `--cleanenv` and binds the cache to `/templateflow`.                                                                                                             |
| Use staged Nextflow runs for normal execution; keep standalone diagnostics in separate scratch space.                         | [Production checkpoints](production_workflow_guide.md) preserve the current gate, cache, and output publishing behavior.                                                                                            |

MRIQC’s current participant and group wrappers retain `--no-sub`, disabling submission of quality metrics to its metrics repository ([MRIQC documentation](https://mriqc.readthedocs.io/en/latest/usage.html)). fMRIPrep also passes `--notrack`. These flags do not guarantee offline execution: reference downloads and container preparation still depend on the configured environment.

## Standalone container guide retained from the prototype

The following instructions incorporate the precursor's conversion, validation, quality-control, preprocessing and defacing recipes directly into this repository. They are adapted to the inspected `dev` implementation; the prototype's old image versions and site-specific scripts are not drop-in replacements. Use the [staged Nextflow guide](production_workflow_guide.md) for normal production runs. These standalone commands are for isolating application problems in a separate scratch directory: they do not reproduce Nextflow's session-aware configuration generation, postprocessing, merged-dataset assembly, validation gate, cache or publication rules.

### 1. Prepare images and paths

Use Bash and Apptainer on Linux. Obtain the custom images from your site maintainer, configure the actual paths below, and check the installed executables. These examples use the image names in the current wrappers; filenames are not proof of the installed version. The prototype's MRIQC 24.0.2 and fMRIPrep 24.0.1 recipes have been updated to the current image defaults, while the custom PyDeface image requires an actual package-version check.

```bash
set -euo pipefail
CONTAINERS=/srv/containers
DCM2BIDS_IMAGE="$CONTAINERS/dcm2bids_3.2.0.sif"
VALIDATOR_IMAGE="$CONTAINERS/bidsvalidator_bash.sif"
MRIQC_IMAGE="$CONTAINERS/mriqc_25.0.0rc0.sif"
FMRIPREP_IMAGE="$CONTAINERS/fmriprep_24.1.1.sif"
PYDEFACE_IMAGE="$CONTAINERS/pydeface_3.0.sif"

# Replace these paths with an existing study and a fresh diagnostic directory.
DICOM_DIR=/data/dicom/STUDY_001_S01
CONFIG=/data/study/dcm2bids_config.json
BIDS_ROOT=/data/study/reviewed_bids
SCRATCH=/scratch/neuromriprep-diagnostics
SUBJECT=001
SESSION=01
FS_LICENSE=/data/study/license.txt
BIDS_FILTER=/data/study/bids_filter.json
TF_CACHE=/srv/templateflow
THREADS=16
OMP_THREADS=4
mkdir -p "$SCRATCH" "$SCRATCH/logs"

apptainer exec "$DCM2BIDS_IMAGE" dcm2bids --version
apptainer exec "$VALIDATOR_IMAGE" bash -c 'command -v bids-validator && bids-validator --version'
apptainer run "$MRIQC_IMAGE" --version
apptainer exec "$FMRIPREP_IMAGE" fmriprep --version
apptainer exec "$PYDEFACE_IMAGE" python3 -c 'from importlib.metadata import version; print(version("pydeface"))'
sha256sum "$DCM2BIDS_IMAGE" "$VALIDATOR_IMAGE" "$MRIQC_IMAGE" \
    "$FMRIPREP_IMAGE" "$PYDEFACE_IMAGE" > "$SCRATCH/container-sha256.txt"
```

Run the examples in the same Bash session, or include this setup at the top of each script. `BIDS_ROOT` must contain the complete reviewed dataset, including `dataset_description.json` and an appropriate lowercase `.bidsignore`. Supply an existing filter JSON (`{}` selects without additional filtering), FreeSurfer license and populated TemplateFlow cache before preprocessing. Set the runtime's bind mounts to include any other input/reference paths used by your study.

The supported conversion image can be obtained with:

```bash
apptainer pull "$DCM2BIDS_IMAGE" docker://unfmontreal/dcm2bids:3.2.0
```

Create the destination directory first and use this only if the image is absent. The repository does not supply reproducible builds for every custom image. In particular, verify that the validator image has Bash and produces the text format expected by the gate; merely renaming a historical SIF is insufficient. Use site-provided proxy and trusted certificate settings for reference downloads. Do not disable TLS certificate verification. A prepopulated cache can avoid downloads, but `--no-sub` and `--notrack` alone do not make an application offline.

### 2. Convert one acquisition directory

A typical input layout is:

```text
/data/dicom/
└── STUDY_001_S01/          # one samplesheet row; subject 001, session 01
    └── scan_date/
        ├── anatomical_series/   # DICOM files
        ├── functional_series/   # DICOM files
        └── fieldmap_series/     # DICOM files
```

The inner directory names depend on the scanner export. The current Nextflow parser uses the outer basename, not the acquisition date, to derive subject/session labels. The standalone command below sets those labels explicitly:

```bash
mkdir -p "$SCRATCH/conversion"
apptainer exec --cleanenv \
    -B "$DICOM_DIR:/dicom:ro" -B "$CONFIG:/config.json:ro" \
    -B "$SCRATCH/conversion:/output" \
    "$DCM2BIDS_IMAGE" dcm2bids \
    -d /dicom -p "$SUBJECT" -s "ses-$SESSION" \
    -c /config.json -o /output \
    2>&1 | tee "$SCRATCH/logs/dcm2bids.log"
```

Inspect `sub-001/ses-01/{anat,func,fmap,dwi}` as applicable to the acquired modalities, associated JSON files and conversion logs. The [converted dataset example](output.md#example-converted-dataset) shows expected naming and sidecars. Do not assume that a successful conversion also performs the current workflow's JSON edits or dataset-level assembly. For multiple acquisitions, repeat with distinct subject/session labels and their reviewed mappings, or use the samplesheet-driven workflow. Never combine projects with colliding identifiers into a shared output root.

### 3. Validate the complete dataset

```bash
validator_status=0
apptainer exec --cleanenv -B "$BIDS_ROOT:/bids:ro" \
    "$VALIDATOR_IMAGE" bids-validator /bids --verbose \
    > "$SCRATCH/logs/validator.log" 2>&1 || validator_status=$?
printf 'Validator exit status: %s\n' "$validator_status"
cat "$SCRATCH/logs/validator.log"
```

Review both the exit status and findings. This command does not apply the production warning allowlist. In Nextflow, `BIDS_VALIDATOR` records its status and exits successfully so that `BIDS_QC_GATE` can inspect the report. A missing downstream dataset can therefore indicate a rejected gate even when Nextflow exits successfully. Resolve unexpected errors and warnings before running subsequent diagnostics.

When an acquisition is incomplete, investigate `BOLD_NOT_4D` and `NIFTI_PIXDIM4` against the scanner record and image dimensions. If a run is excluded after review, correct both filenames and field-map associations in the conversion mapping, regenerate the dataset, and validate again. `IntendedFor` must refer to retained targets; `B0FieldIdentifier` and `B0FieldSource` must remain consistent. Do not automatically remove `run-01` when only one run remains. Record exclusions and reasons in study provenance.

Use `.bidsignore` only for reviewed non-BIDS artifacts. The current postprocessor already handles ADC outputs, SBRef gradient files and temporary conversion artifacts; importing the prototype's ignore list wholesale can hide genuine problems. Inconsistent subject content, acquisition parameters or missing sessions should be reconciled with the study design before accepting the actual warning code.

### 4. Run MRIQC and review reports

```bash
mkdir -p "$SCRATCH/mriqc" "$SCRATCH/mriqc-work"
apptainer run \
    -B "$BIDS_ROOT:/input_dir:ro" \
    -B "$SCRATCH/mriqc:/output_dir" \
    -B "$SCRATCH/mriqc-work:/work_dir" \
    "$MRIQC_IMAGE" /input_dir /output_dir participant \
    --participant-label "$SUBJECT" \
    --nprocs "$THREADS" --omp-nthreads "$OMP_THREADS" --mem_gb 30 \
    --no-sub -v --verbose-reports --work-dir /work_dir \
    2>&1 | tee "$SCRATCH/logs/mriqc-participant.log"

# Aggregate the participant outputs already present in this same output directory.
apptainer run \
    -B "$BIDS_ROOT:/input_dir:ro" \
    -B "$SCRATCH/mriqc:/output_dir" \
    "$MRIQC_IMAGE" /input_dir /output_dir group --no-sub --mem_gb 30 \
    2>&1 | tee "$SCRATCH/logs/mriqc-group.log"
```

For a whole project, omit `--participant-label "$SUBJECT"` from the participant command, or supply several labels after that flag. Run group aggregation only after the intended participant outputs are complete. Inspect individual HTML reports, image-quality metrics and group summaries; successful execution does not establish image suitability. `--no-sub` prevents submission of metrics to the MRIQC repository. The production group wrapper copies participant results to a separate publication directory and hard-codes its image path, as documented in [setup](usage.md#5-configure-images-resources-and-reference-data).

### 5. Run fMRIPrep for one participant across selected sessions

```bash
mkdir -p "$SCRATCH/fmriprep/sub-$SUBJECT" "$SCRATCH/fmriprep-work/sub-$SUBJECT"
apptainer exec --cleanenv \
    -B "$BIDS_ROOT:/bids:ro" \
    -B "$SCRATCH/fmriprep/sub-$SUBJECT:/output" \
    -B "$SCRATCH/fmriprep-work/sub-$SUBJECT:/work" \
    -B "$FS_LICENSE:/license.txt:ro" \
    -B "$BIDS_FILTER:/filter.json:ro" \
    -B "$TF_CACHE:/templateflow" \
    --env TEMPLATEFLOW_HOME=/templateflow \
    "$FMRIPREP_IMAGE" fmriprep /bids /output participant \
    --participant-label "$SUBJECT" --fs-license-file /license.txt \
    --bids-filter-file /filter.json --notrack \
    --omp-nthreads "$OMP_THREADS" --random-seed 13 --skull-strip-fixed-seed \
    --output-spaces MNI152NLin2009cAsym MNI152NLin6Asym \
    --work-dir /work \
    2>&1 | tee "$SCRATCH/logs/fmriprep-sub-$SUBJECT.log"
```

Unlike the current Nextflow wrapper, this diagnostic command retains fMRIPrep's own validation because it has no upstream production gate. After a separately verified gate, the wrapper uses `--skip_bids_validation`. The participant's selected sessions remain together; do not copy each session into an artificial single-session dataset. Inspect the filter JSON before restricting sessions or modalities. The default current wrapper does not enable `--longitudinal`; longitudinal processing is a separate reviewed choice, not implied by the presence of multiple sessions.

For a project, run the command once per **unique participant**, using separate work/output paths as above. Do not iterate samplesheet session rows as if they were unique participants. The current Nextflow duplicate-participant limitation is described in [pipeline architecture](pipeline.md#current-development-limitations). Review the anatomical/functional alignment reports, confounds and missing/failed runs before analysis. fMRIPrep outputs are preprocessing derivatives; nuisance-regression and other downstream statistical choices remain the analyst's responsibility.

### 6. Deface an anatomical image without overwriting the source

```bash
ANAT_DIR="$BIDS_ROOT/sub-$SUBJECT/ses-$SESSION/anat"
INPUT_NAME="sub-${SUBJECT}_ses-${SESSION}_T1w.nii.gz"
mkdir -p "$SCRATCH/defaced/sub-$SUBJECT/ses-$SESSION/anat"
apptainer exec --cleanenv \
    -B "$ANAT_DIR:/input:ro" \
    -B "$SCRATCH/defaced/sub-$SUBJECT/ses-$SESSION/anat:/output" \
    --env OMP_NUM_THREADS="$OMP_THREADS" \
    "$PYDEFACE_IMAGE" pydeface "/input/$INPUT_NAME" \
    --outfile "/output/${INPUT_NAME%.nii.gz}_defaced.nii.gz" \
    2>&1 | tee "$SCRATCH/logs/pydeface-sub-${SUBJECT}-ses-${SESSION}.log"
```

Set `INPUT_NAME` to the actual converted file, including any acquisition/run entities. For a project, enumerate original anatomical images and preserve participant/session directories in the destination; skip existing `_defaced` files and verify every selected input has an output. The production PyDeface branch selects anatomical `.nii.gz` files; the benchmark specifically selects compressed T1-weighted images and runs all four methods. Use the [defacing benchmark guide](benchmark.md) for a reproducible multi-method comparison rather than extrapolating from this one-image diagnostic.

Inspect the original and defaced images for residual facial structures and unintended removal of brain tissue. Keep defaced outputs separate until release review is complete. Successful tool execution, low voxel differences or a detector pass do not establish anonymity. In the current production workflow, fMRIPrep and MRIQC process the original post-gate BIDS dataset independently of defacing.

### 7. Return to the managed workflow

Preserve diagnostic logs, actual image versions and checksums with the issue being investigated. Apply any confirmed data/configuration correction to the study inputs, then resume the staged Nextflow run from its original launch/work directories. Standalone outputs are not Nextflow cache entries; copying them into published result folders will not integrate them into task provenance. These recipes were syntax-checked and compared with the current wrappers; they have not been executed on study data or with the institution's SIF images here.
