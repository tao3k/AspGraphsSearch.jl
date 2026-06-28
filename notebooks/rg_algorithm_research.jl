### A Pluto.jl notebook ###
# v0.20.27

using Markdown
using InteractiveUtils

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using AspGraphsSearch
    using DataFrames
    using Graphs
    using Plots
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0002
md"""
# ASP rg algorithm research

This notebook studies ripgrep as an algorithmic stage in the ASP search flow.
The focus is pattern selectivity, path and language filtering, repeated scan
pressure, and which rg searches should be replaced by provider-owned structural
or graph queries.

Current artifacts distinguish raw `rg` shell commands from ASP provider
`search pattern` commands. Raw `rg` can be zero while provider pattern-search
still provides evidence for rg-like algorithm research.
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0003
begin
    ASP_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
    ARTIFACT_ROOT = joinpath(ASP_REPO_ROOT, ".cache", "agent-semantic-protocol", "artifacts")
    dataset = artifact_research_dataset_from_repo(ASP_REPO_ROOT)
    rg = artifact_rg_algorithm_analysis(dataset.commands)
    nothing
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0004
function markdown_table(df::DataFrame; limit::Integer = 20)
    shown = first(df, min(Int(limit), nrow(df)))
    columns = names(shown)
    isempty(columns) && return md"_empty table_"

    clean(value) = replace(string(value), "|" => "\\|", "\n" => " ")
    lines = String[]
    push!(lines, "|" * join(columns, "|") * "|")
    push!(lines, "|" * join(fill("---", length(columns)), "|") * "|")
    for row in eachrow(shown)
        push!(lines, "|" * join((clean(row[column]) for column in columns), "|") * "|")
    end
    return Markdown.parse(join(lines, "\n"))
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0005
begin
    function empty_plot(title)
        plot(title = title, legend = false, axis = false, ticks = false)
    end

    function metric_label_column(metrics::DataFrame)
        :label in propertynames(metrics) && return :label
        :node in propertynames(metrics) && return :node
        return first(propertynames(metrics))
    end

    function top_metric_table(metrics::DataFrame)
        nrow(metrics) == 0 && return metrics
        subset = metrics[in.(metrics.kind, Ref(["tool", "query-type", "route-hint", "query"])), :]
        nrow(subset) == 0 && return subset
        sort!(subset, :pagerank, rev = true)
        return first(subset, min(12, nrow(subset)))
    end
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0006
md"""
## Dataset scope
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0007
markdown_table(DataFrame(
    metric = [
        "raw rg command events",
        "provider search pattern events",
        "rg/pattern events",
        "pattern pressure groups",
        "route groups",
        "optimization opportunities",
        "graph vertices",
        "graph edges",
    ],
    value = [
        nrow(rg.raw_events),
        nrow(rg.pattern_events),
        nrow(rg.events),
        nrow(rg.pattern_pressure),
        nrow(rg.route_summary),
        nrow(rg.opportunities),
        nv(rg.graph.graph),
        ne(rg.graph.graph),
    ],
))

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0008
md"""
## Pattern pressure

The research question here is whether rg patterns are selective enough to
justify raw text scanning. Repeated pattern/target pressure is evidence for an
index, a graph lookup, or a structural query replacement.
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0009
markdown_table(rg.pattern_pressure; limit = 30)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0010
begin
    if nrow(rg.pattern_pressure) == 0
        empty_plot("rg pattern pressure")
    else
        labels = string.(rg.pattern_pressure.query_terms)
        bar(labels, rg.pattern_pressure.events,
            xrotation = 35,
            xlabel = "pattern",
            ylabel = "events",
            title = "rg pattern pressure by query",
            legend = false)
    end
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0011
md"""
## Path and route filtering

rg is useful when text is the right primitive. The optimization question is
whether language, provider, path, and graph facts can reduce file-system scans
before rg is invoked.
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0012
markdown_table(rg.route_summary; limit = 30)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0013
markdown_table(rg.opportunities; limit = 30)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0014
md"""
## rg graph centrality

This graph only includes rg events. Central nodes identify repeated patterns,
targets, routes, and language/provider scopes that should be considered for
pre-indexing or provider-owned query routes.
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0015
begin
    rg_rank = top_metric_table(rg.metrics)
    if nrow(rg_rank) == 0 || !(:pagerank in propertynames(rg_rank))
        empty_plot("rg graph centrality")
    else
        label_col = metric_label_column(rg_rank)
        bar(string.(rg_rank[!, label_col]), rg_rank.pagerank,
            xrotation = 35,
            xlabel = "graph node",
            ylabel = "PageRank",
            title = "rg optimization graph PageRank",
            legend = false)
    end
end

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0016
markdown_table(rg_rank; limit = 20)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0017
md"""
## Algorithm experiments to run next
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0018
markdown_table(rg.algorithm_notes; limit = 10)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0019
md"""
## Event evidence
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0020
markdown_table(select(rg.events, [:event_time, :language, :provider, :query_type, :query_terms, :target_hint, :route_hint, :elapsed_ms, :normalized_key]); limit = 50)

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0021
md"""
## Artifact-root coverage

This table enumerates every artifact scope and language with searchable events after repo-level aggregation. Rows marked `search-without-rg-evidence` are not traversal misses; they identify languages or artifact roots where agents searched without emitting raw `rg` or provider `pattern-search` evidence.
"""

# ╔═╡ 5c9d9f58-54c6-11ef-2300-2f2f5a1f0022
markdown_table(
    select(
        rg.coverage,
        [
            :artifact_scope,
            :language,
            :searchable_events,
            :rg_events,
            :raw_rg_events,
            :provider_pattern_events,
            :rg_coverage_status,
        ],
    );
    limit = 50,
)

# ╔═╡ Cell order:
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0001
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0002
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0003
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0004
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0005
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0006
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0007
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0021
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0022
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0008
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0009
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0010
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0011
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0012
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0013
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0014
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0015
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0016
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0017
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0018
# ╟─5c9d9f58-54c6-11ef-2300-2f2f5a1f0019
# ╠═5c9d9f58-54c6-11ef-2300-2f2f5a1f0020
