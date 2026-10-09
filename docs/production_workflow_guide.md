# Production workflow: step-by-step execution

Complete the [technical setup](usage.md) first, including the local `site.config`, `params.yaml`, required policy files, images, and fMRIPrep inputs. Commands below run from the repository root. Replace `/scratch/neuromriprep-work` with the same reflink-capable work directory in every invocation. The parameter file must retain `skip_mriqc: false` and `skip_fmriprep: false` for this staged sequence.

## 1. Convert and validate

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  -work-dir /scratch/neuromriprep-work \
  --stop_bidsval true --stop_mriqc true --stop_fmriprep true
```

Check the parsed participant/session names, converted acquisitions, field-map associations, `dataset_validation_log.txt`, and `bids_qc_summary.txt` under your output directory. The gate should report `check_passed: True` before continuing. Correct conversion inputs or mappings and rerun with `-resume` when needed. Accept only reviewed warning codes in the allowlist. A pipeline success message alone does not mean the gate passed.

## 2. Run and review MRIQC

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  -work-dir /scratch/neuromriprep-work -resume \
  --stop_bidsval false --stop_mriqc true --stop_fmriprep true
```

Inspect participant HTML reports, image-quality metrics, and group results under `derivatives/mriqc/`. Review motion, artifacts, coverage, and outliers in the context of your study. MRIQC does not automatically exclude problematic images. Record decisions and, if needed, prepare an explicit fMRIPrep participant list or BIDS filter.

Keep `stop_fmriprep` true here: `stop_mriqc` alone does not disable the independent defacing branch.

## 3. Run and review fMRIPrep

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  -work-dir /scratch/neuromriprep-work -resume \
  --stop_bidsval false --stop_mriqc false --stop_fmriprep true
```

Inspect HTML reports under `derivatives/fmriprep/`, registration and normalization, tissue segmentation, functional preprocessing, and confounds. Reconcile completed participants against those requested. The example parameter file sets `ignore_fmriprep_fail: false`; the repository default can ignore failures after one retry. Resolve the repeated-subject task limitation before using a multi-session samplesheet.

## 4. Generate and review defaced images

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  -work-dir /scratch/neuromriprep-work -resume \
  --stop_bidsval false --stop_mriqc false --stop_fmriprep false \
  --deface_tool pydeface
```

Review anatomical results in `derivatives/defaces/` for residual facial features and unintended removal of brain tissue. Production defacing does not automatically run the benchmark renderer or detector. Defaced images are separate copies: raw BIDS images, fMRIPrep derivatives, sidecars and logs can still contain identifying information. Review the specific files intended for release; do not distribute the entire results directory as an anonymized dataset.

## Other execution patterns

With both skip flags false, the following combinations select the intended stages (subject to the production BIDS gate):

| `stop_bidsval` | `stop_mriqc` | `stop_fmriprep` | Enabled work                                          |
| -------------- | ------------ | --------------- | ----------------------------------------------------- |
| true           | any          | any             | Conversion and validation only.                       |
| false          | true         | true            | Conversion, validation, MRIQC.                        |
| false          | false        | true            | Above plus fMRIPrep.                                  |
| false          | false        | false           | All stages; downstream branches may run concurrently. |
| false          | true         | false           | MRIQC and defacing, but no fMRIPrep.                  |

For an unattended full run, use step 4 without `-resume` for a new run, after validating the study setup. It does not wait for human review between branches.

For conversion/validation followed by defacing only:

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  -work-dir /scratch/neuromriprep-work -resume \
  --stop_bidsval false --skip_mriqc true --skip_fmriprep true \
  --stop_mriqc false --stop_fmriprep false --deface_tool pydeface
```

In the current code, fMRIPrep is eligible when `!stop_mriqc || skip_mriqc` and not `skip_fmriprep`; defacing is eligible when `!stop_fmriprep || skip_fmriprep`. All are enclosed by `!stop_bidsval`. Therefore a skip flag is not a pause flag. Explicitly supply the complete combination when deviating from the staged guide.

Only after manually reviewing all remaining BIDS findings should you consider `--enforce_bidsqc_gate false`. This reports the result but removes its downstream block; it does not repair validation issues.

## Resume and completion checklist

Use `nextflow log` to inspect previous runs; `-resume RUN_NAME` selects a particular cache. Keep the launch `.nextflow/` cache and work directory intact. Confirm expected subjects and outputs at each stage, preserve reports, and archive the software/configuration provenance before cleaning work files. See [outputs and diagnostics](output.md).
