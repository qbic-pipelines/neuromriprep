# Defacing benchmark

`--mode benchmark_defacing` compares PyDeface, MRI Deface, FSL Deface, and AFNI Refacer on the same converted anatomical inputs. It performs its own DICOM conversion, postprocessing, merge, ignore handling, and validation, then selects original compressed `*_T1w.nii.gz` files from each subject/session `anat/` directory. It does not run MRIQC or fMRIPrep.

Unlike production, this mode does not invoke the BIDS QC gate or the optional output-patch subworkflow. The production stop flags, `deface_tool`, and production defacing participant list do not control its four-method comparison. Limit the input samplesheet to the intended benchmark cohort and inspect the task-local validator log yourself.

## Workflow diagram

![Thesis metro diagram comparing PyDeface, AFNI Refacer, MRI Deface, and FSL Deface, followed by QC rendering, metrics, and automated detection.](images/thesis-benchmark-metro.png)

_Böhme (2026), Figure 3.3, printed p. 49. This is the thesis diagram: its BIDS QC gate station is not executed by the current benchmark workflow. Validation runs, but gate enforcement is production-only. [Figure source details](images/README.md)._

## Setup and execution

For a dedicated `benchmark.config`, minimal parameter file, and end-to-end commands, follow the [README benchmark walkthrough](../README.md#defacing-benchmark). The instructions below show the alternative of extending an existing production configuration.

1. Complete the common [technical setup](usage.md): samplesheet, conversion configuration, ignore files, compatible scratch storage, and Apptainer.
2. Configure all four defacer images and the rendering/metrics/detector environments. Their default SIF paths are institutional; the following additional `site.config` entries illustrate overrides (replace the paths).

```groovy
process {
    withName: 'MRI_DEFACE' {
        ext.container = '/srv/containers/mri_deface.sif'
    }
    withName: 'FSL_DEFACE' {
        ext.container = '/srv/containers/fsl_deface.sif'
    }
    withName: 'AFNI_REFACER' {
        ext.container = '/srv/containers/afni_refacer_pennlinc.sif'
    }
    withName: 'DEFACE_QC_RENDER|DEFACE_METRICS' {
        ext.container = '/srv/containers/deface_benchmark.sif'
    }
    withName: 'DEFACE_DETECTOR' {
        ext.container = '/srv/containers/deface_detector.sif'
    }
}
```

The production example already overrides `PYDEFACE`. MRI Deface requires its brain and face templates. The rendering/metrics image must satisfy imports in `assets/scripts/deface_qc_render.py` and `deface_metrics.py`; the detector needs Node.js and dependencies used by `mri_deface_detector.mjs`. The model files are included in `assets/mri-deface-detector/model_js/`. `MERGE_BENCHMARK` has no container directive: Python 3 and pandas must be available on its execution host, or supply an appropriate process `container` override for that task.

3. Launch a small benchmark first, with separate output and work directories:

```bash
nextflow run . -profile apptainer -c site.config -params-file params.yaml \
  --mode benchmark_defacing --input /data/study/benchmark_samplesheet.csv \
  --outdir /data/study/benchmark-results \
  -work-dir /scratch/neuromriprep-benchmark-work
```

Reuse the same command with `-resume` after correcting inputs or setup. The mode override replaces `mode: production` from the shared parameter file. The benchmark runs all four methods regardless of production stop/skip flags.

## Review

Check that every intended image has results for each method, inspect PNG comparisons, and read the per-image CSV before interpreting aggregate summaries. Review residual facial structure, brain preservation, and unexpected changes. The detector runs with threshold 0.5; its score is a model output, not a calibrated privacy guarantee. Quantitative image-change measures also cannot by themselves distinguish successful face removal from unwanted tissue removal.

Böhme's thesis combined visual inspection, image-change metrics, and automated detection, finding disagreement between detector classifications and manual judgments. Its findings concern the evaluated dataset and software environment; evaluate your own acquisitions rather than choosing a method solely from that ranking. See [thesis notes](pipeline.md#thesis-and-source-notes) and [published outputs and publication caveats](output.md#benchmark-outputs).
