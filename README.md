# AspGraphsSearch.jl

`AspGraphsSearch.jl` is the Julia analyzer for studying ASP search/query workflows and graph-search algorithms. It sits under `agent-semantic-protocols/analyzers` next to `WendaoGraph.jl` and `ScienceResearch.jl`.

The package has two jobs:

1. Study `asp <language> search/query` workflows as graph algorithms, using `DataFrames.jl` for tabular evidence, `Graphs.jl` for the graph layer, `Plots.jl` for notebook charts, and `ScienceResearch.jl` for research experiment contracts.
2. Analyze `.cache/agent-semantic-protocol/artifacts` search/query command traces so ASP code and documentation search can be improved with replayable evidence.

Python `asp_graph_turbo` already owns the production-side graph-turbo and recommendation lane. This package is research-first: notebook evidence, complex algorithm experiments, dataset/workload descriptors, and static HTML publication.

## Setup

From this package:

```sh
julia --project=. -e 'using Pkg; Pkg.develop(path="../ScienceResearch.jl"); Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
```

`ScienceResearch.jl` is a sibling analyzer submodule in the parent repository. Use `Pkg.develop(path="../ScienceResearch.jl")` so local research follows the checked-out submodule rather than an external registry assumption.

## Research Docs

The research contract follows the parent repository's Johnny Decimal Org layout:

- `docs/10-19-research/10.01-asp-artifacts-data-science.org`
- `docs/10-19-research/10.01-asp-artifacts-data-science/10.01.00-overview.org`
- `docs/10-19-research/10.01-asp-artifacts-data-science/10.01.10-artifact-data-contract.org`
- `docs/10-19-research/10.01-asp-artifacts-data-science/10.01.20-action-flow-reconstruction.org`
- `docs/10-19-research/10.01-asp-artifacts-data-science/10.01.30-algorithm-experiments.org`
- `docs/10-19-research/10.01-asp-artifacts-data-science/10.01.40-instrumentation-gaps.org`

Start there before changing the analysis pipeline.

## JSON Artifact Dataset

The main DataScience entry point reads artifact JSON with `JSON.jl`, normalizes it into `DataFrames.jl` tables, and constructs a `Graphs.jl` action-flow graph.

```julia
using AspGraphsSearch

root = joinpath(dirname(@__DIR__), "..", ".cache", "agent-semantic-protocol", "artifacts")
dataset = artifact_research_dataset(root)

dataset.inventory      # JSON inventory with schema/method/language/provider fields
dataset.packets        # search/query packet table
dataset.commands       # provider command rows with argv, latency, exit code
dataset.taxonomy       # language/provider/operation command taxonomy
dataset.phases         # weak mtime-based phases until event IDs exist
dataset.flow           # ArtifactActionFlowGraph
dataset.flow_metrics   # PageRank/degree metrics by typed node
```

Use `dataset.taxonomy`, `dataset.phases`, and `dataset.flow_metrics` as the first triage surfaces for improving ASP code and docs search.

## fzf/rg Search Optimization Analyzer

The search optimization layer turns provider command rows into a route-promotion graph:

```julia
dataset = artifact_research_dataset(root)
optimization = artifact_search_optimization_analysis(dataset.commands)

optimization.events         # fzf/rg/prime/query/direct-source-read event table
optimization.summary        # tool/query-type counts and latency
optimization.graph          # typed tool/query/route graph
optimization.metrics        # degree and PageRank over optimization graph
optimization.opportunities  # repeat-search, latency, fzf/rg promotion, time gaps
```

Use this before changing ASP search behavior. It separates repeated `fzf` discovery, repeated `rg` patterns, structural query routes, direct source reads, and time instrumentation gaps so improvements can be tied to observed command flow.

Use the split tool analyzers for deeper algorithm work:

```julia
fzf = artifact_fzf_algorithm_analysis(dataset.commands)
rg = artifact_rg_algorithm_analysis(dataset.commands)
```

The fzf analyzer focuses on candidate-set pressure, repeated fuzzy query reuse,
route-promotion opportunities, and the missing instrumentation needed to measure
candidate pruning. The rg analyzer focuses on pattern selectivity, path and
language filtering, repeated scan pressure, and structural query replacement.

## Legacy Artifact Command Graph

```julia
using AspGraphsSearch

root = joinpath(dirname(@__DIR__), "..", ".cache", "agent-semantic-protocol", "artifacts")
records = collect_search_commands(root)
graph = search_command_graph(records)
summary = summarize_search_graph(graph)
spec = research_experiment_spec(records; root)
```

`records` captures source file, command text, language facade, verb, and arguments for `asp ... search/query` commands. `search_command_graph` builds a `Graphs.jl` directed graph over file, command, language, and verb nodes.

## Algorithm Analysis

The Julia analysis mirrors the Python `asp_graph_turbo` shape at research depth: command tables, graph metrics, personalized rank, and opportunity scoring.

```julia
analysis = artifact_algorithm_analysis(records; root)

analysis.commands            # DataFrame of command records
analysis.graph_metrics       # degree, PageRank, component by graph node
analysis.personalized_rank   # typed-PPR-style rank seeded from search/pipe/prime
analysis.opportunities       # ranked improvement points
```

Use `analysis.opportunities` as the baseline text-artifact comparison surface. It highlights missing language facades, repeated operations such as `pipe`/`prime`, repeated command shapes, artifact file hubs, and graph-rank hotspots.

## Pluto To HTML

The notebook surfaces are:

- `notebooks/artifacts_search_commands.jl`
- `notebooks/search_optimization_algorithms.jl`
- `notebooks/fzf_algorithm_research.jl`
- `notebooks/rg_algorithm_research.jl`

Build static HTML through the ScienceResearch publication helper:

```sh
julia --project=. scripts/build_notebook_html.jl
```

The script writes HTML under `public/`. Notebook evidence should point at machine-readable artifacts with `scienceresearch-artifact: <relative-path>` before publication.
