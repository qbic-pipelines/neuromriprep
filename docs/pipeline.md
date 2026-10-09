# Pipeline architecture and scientific context

## Scope

neuromriprep coordinates tools that were previously run through separate Bash scripts. Nextflow manages task dependencies, resource requests, caching, and restartable execution. The input is DICOM organized by participant/session; direct entry from an existing BIDS dataset is not exposed by the current entry workflow. The result is a merged BIDS dataset, optional MRIQC and fMRIPrep derivatives, and separate defaced anatomical images. Statistical analysis of fMRI data is outside this workflow.

## FAIR-oriented infrastructure and NFDI context

[Sezer et al. (2026), §§III–V](https://doi.org/10.5281/zenodo.22099332) place neuromriprep within the IRTG 2804 research data management infrastructure. The paper describes de.NBI Cloud computation using Slurm, Apptainer, and shared storage; OMERO manages images, while linked study metadata provide experimental context. Section V names `qbic-pipelines/neuromriprep` as an MRI workflow under development at QBiC, following nf-core principles but not yet part of nf-core.

For this repository, the practical contribution to FAIR (Findable, Accessible, Interoperable, Reusable) data handling is BIDS organization and validation, reproducible processing definitions, and reviewable derivatives. Interpret these as workflow contributions within a larger data lifecycle: controlled access, metadata cataloguing, persistent identifiers, and archival/publication arrangements require the surrounding services. The current entry workflow consumes local DICOM paths; it does not implement OMERO ingestion, REMBI metadata synchronization, or repository deposition. The paper’s broader anonymization description should not be read as a guarantee that this checkout removes every identifying metadata field.

The connection to NFDI is alignment with its research data management goals, rather than an ownership claim. [NFDI4BIOIMAGE](https://www.nfdi.de/consortia-nfdi4bioimage/?lang=en) emphasizes standardized formats, metadata, analysis provenance, and reusable workflows for bioimaging. Those aims provide relevant context for this architecture; the cited paper identifies the deployment as de.NBI/QBiC infrastructure and does not establish neuromriprep as an NFDI service. See the [full reference](../CITATIONS.md#fair-oriented-research-data-management).

## Production stages

| Stage            | Implementation                                                            | Behavior                                                                                                                                                                     |
| ---------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Input metadata   | `main.nf`, `workflows/neuromriprep.nf`                                    | Read `project,dicom_dir`; derive subject and session from directory basename.                                                                                                |
| Conversion       | `subworkflows/local/bidsing/main.nf`                                      | Modify field-map identifiers for each session, run dcm2bids, optionally apply the selected-participant metadata patch.                                                       |
| Postprocessing   | `modules/local/dcm2bidspostprocess/main.nf`                               | Remove the exact `Acquisitionduration` key from BOLD JSON; move files containing `adc` to ADC derivatives; remove DWI sbref bval/bvec files. These are study-specific rules. |
| Dataset assembly | `modules/local/mergebidsdataset/main.nf`                                  | Merge subjects/sessions, create `dataset_description.json` with BIDSVersion 1.9.0, collect conversion logs. Requires reflink-capable storage.                                |
| Validation       | `modules/local/bidsignore/main.nf`, `modules/local/bidsvalidator/main.nf` | Apply `.bidsignore` additions/removals and capture verbose validator output.                                                                                                 |
| QC gate          | `assets/scripts/bids_gate.py`                                             | Block downstream data when parsed errors or non-allowlisted warnings are present, unless enforcement is disabled.                                                            |
| MRIQC            | `subworkflows/local/mriqc_participants/main.nf`                           | One participant-level invocation over the dataset (optionally selected subjects), followed by group aggregation.                                                             |
| fMRIPrep         | `subworkflows/local/fmriprep_participants/main.nf`                        | Construct tasks from input rows; use the original merged BIDS data, FreeSurfer license, and BIDS filter.                                                                     |
| Defacing         | `workflows/neuromriprep.nf`                                               | Apply one selected method to compressed anatomical NIfTI files in each input subject/session.                                                                                |

MRIQC measures image quality; it does not decide which participants to exclude. fMRIPrep performs anatomical and functional preprocessing using its own workflows. The wrapper requests `MNI152NLin2009cAsym` and `MNI152NLin6Asym` spaces, a random seed of 13, fixed skull-stripping seed, and skips its internal BIDS validation because this pipeline provides a separate validation stage. Review the actual reports and confounds before downstream analysis.

## Execution dependencies and checkpoints

MRIQC, fMRIPrep, and defacing branch from the same BIDS dataset after the gate. They do not consume each other's outputs. Only MRIQC group processing depends on MRIQC participant processing. Enabling all stages therefore permits concurrent execution, not a strict MRIQC → fMRIPrep → defacing sequence.

The stop flags select branches at launch; they do not pause a running process for interactive approval. Use separate resumed invocations to implement human review. The [production guide](production_workflow_guide.md) gives combinations that account for the current independent branch conditions.

A QC gate rejection filters the downstream channel rather than failing the Nextflow run. A successful Nextflow exit is therefore insufficient evidence that all intended processing occurred. The gate parses textual validator issue patterns: inspect the raw validator log too, especially after changing validator versions or if a tool fails without recognizable issue lines.

## Current development limitations

- Container defaults and several inputs refer to local `/nic/sw/IRTG` resources. Required study assets are excluded from Git. MRIQC group has a hard-coded image path with no parameter override.
- Both modes merge all samplesheet rows into one dataset; use one study per invocation and avoid duplicate subject/session rows.
- fMRIPrep metadata are not deduplicated by subject. Multiple sessions for the same subject can schedule duplicate participant jobs writing identical published paths. Review or fix task deduplication before a multi-session production run.
- Each modified dcm2bids configuration is published as `modified_config.json`; multiple rows can overwrite that root filename. Retain the work directory for per-task provenance.
- Ignored fMRIPrep failures are enabled by default; the guide opts out so incomplete runs are easier to detect.
- The `run_complete` parameter is declared but not used to enable stages. Use all three stop flags explicitly.
- nf-schema initialization/completion calls are commented out in `main.nf`. The schema, `--help`, and template tests should not be relied upon as a complete MRI interface.
- Version aggregation contains only records wired into the selected workflow. It is not a full inventory of every container/tool.

## Thesis and source notes

Scientific and design context comes from:

> Lorena Böhme (2026). _neuromriprep: A Nextflow Pipeline for Reproducible Preprocessing and Anonymization for Functional MRI Data_. Master's thesis in Bioinformatics, University of Tübingen. Title-page date: 23 July 2026.

Relevant printed-page references are §§2.2–2.7 (pp. 19–35: conversion, QC, preprocessing and defacing), §3.1 (pp. 39–47: production design), §3.2 (pp. 47–52: benchmark), and §§4.5–4.7 (pp. 69–72: interpretation and limitations). The PDF supplied for documentation is not redistributed in this repository and no public thesis URL or DOI is assumed.

The thesis reports approximately 78 hours of summed task runtime and 19 hours elapsed for its evaluated production run; these are study-specific observations, not resource guarantees. Its visual evaluation found successful defacing for 60 of 62 images with each of PyDeface and AFNI Refacer. Automated detector results disagreed with manual ratings, supporting combined visual and quantitative review rather than treating detector output as ground truth.

Operational instructions follow the current code where wording differs from the thesis: reflink copies are mandatory, some reports remain task-local, and the defacing branch is controlled independently of `stop_mriqc`. No universal anonymization guarantee or benchmark ranking for other datasets follows from the thesis evaluation.
