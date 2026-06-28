### A Pluto.jl notebook ###
# v0.20.27

using Markdown
using InteractiveUtils

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using AspGraphsSearch
    using DataFrames
    using Graphs
    using Plots
end

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0002
md"""
# ASP fzf algorithm research

This notebook studies fzf as an algorithmic stage in the ASP search flow. The
focus is candidate-set construction, fuzzy selection pressure, repeated query
reuse, and whether an interactive fuzzy step should be promoted to a
provider-owned owner/dependency/structural route.
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0003
begin
    ASP_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
    ARTIFACT_ROOT = joinpath(ASP_REPO_ROOT, ".cache", "agent-semantic-protocol", "artifacts")
    dataset = artifact_research_dataset_from_repo(ASP_REPO_ROOT)
    fzf = artifact_fzf_algorithm_analysis(dataset.commands)
    nothing
end

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0004
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

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0005
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

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0006
md"""
## Dataset scope
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0007
markdown_table(DataFrame(
    metric = [
        "fzf events",
        "candidate pressure groups",
        "route groups",
        "optimization opportunities",
        "graph vertices",
        "graph edges",
    ],
    value = [
        nrow(fzf.events),
        nrow(fzf.candidate_pressure),
        nrow(fzf.route_summary),
        nrow(fzf.opportunities),
        nv(fzf.graph.graph),
        ne(fzf.graph.graph),
    ],
))

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0008
md"""
## Candidate-set pressure

The research question here is whether fzf is receiving a small provider-ranked
candidate set or being used as a broad search primitive. Repeated normalized
query pressure is a direct signal for memoization or route promotion.
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0009
markdown_table(fzf.candidate_pressure; limit = 30)

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0010
begin
    if nrow(fzf.candidate_pressure) == 0
        empty_plot("fzf candidate pressure")
    else
        labels = string.(fzf.candidate_pressure.query_terms)
        bar(labels, fzf.candidate_pressure.events,
            xrotation = 35,
            xlabel = "query terms",
            ylabel = "events",
            title = "fzf candidate pressure by query",
            legend = false)
    end
end

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0011
md"""
## Route-promotion opportunities

fzf should usually be late-stage selection. If the artifacts show repeated fzf
calls for owner, dependency, or structural intent, the algorithmic improvement
is to promote the query into ASP provider routes before fuzzy scoring.
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0012
markdown_table(fzf.route_summary; limit = 30)

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0013
markdown_table(fzf.opportunities; limit = 30)

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0014
md"""
## fzf graph centrality

This graph only includes fzf events. Central nodes identify the query types,
routes, targets, and normalized query keys that dominate fuzzy selection.
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0015
begin
    fzf_rank = top_metric_table(fzf.metrics)
    if nrow(fzf_rank) == 0 || !(:pagerank in propertynames(fzf_rank))
        empty_plot("fzf graph centrality")
    else
        label_col = metric_label_column(fzf_rank)
        bar(string.(fzf_rank[!, label_col]), fzf_rank.pagerank,
            xrotation = 35,
            xlabel = "graph node",
            ylabel = "PageRank",
            title = "fzf optimization graph PageRank",
            legend = false)
    end
end

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0016
markdown_table(fzf_rank; limit = 20)

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0017
md"""
## Algorithm experiments to run next
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0018
markdown_table(fzf.algorithm_notes; limit = 10)

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0019
md"""
## Event evidence
"""

# ╔═╡ 3e3bc91c-54c5-11ef-1f00-2f2f5a1f0020
markdown_table(select(fzf.events, [:event_time, :language, :provider, :query_type, :query_terms, :target_hint, :route_hint, :elapsed_ms, :normalized_key]); limit = 50)

# ╔═╡ Cell order:
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0001
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0002
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0003
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0004
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0005
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0006
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0007
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0008
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0009
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0010
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0011
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0012
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0013
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0014
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0015
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0016
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0017
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0018
# ╟─3e3bc91c-54c5-11ef-1f00-2f2f5a1f0019
# ╠═3e3bc91c-54c5-11ef-1f00-2f2f5a1f0020
