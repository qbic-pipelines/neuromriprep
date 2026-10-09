# neuromriprep documentation

Read these pages in order for a first study run:

1. [Pipeline architecture](pipeline.md): stages, data dependencies, scientific context, and implementation limits.
2. [Technical usage](usage.md): installation prerequisites, samplesheet format, study configuration, containers, and troubleshooting.
3. [Production workflow guide](production_workflow_guide.md): explicit commands for each review checkpoint and resuming a run.
4. [Outputs](output.md): published files, task-local diagnostics, and what to inspect.
5. [Defacing benchmark](benchmark.md): comparing the four methods and interpreting QC results.
6. [Prototype lessons](prototype-notes.md): operational guidance from the precursor project verified against current code.

These pages describe the `dev` source, not a released turnkey package. The parameter schema, template help machinery, and bundled test profile do not yet describe a complete MRI run. Follow the documented source-backed parameters and local setup requirements instead.
