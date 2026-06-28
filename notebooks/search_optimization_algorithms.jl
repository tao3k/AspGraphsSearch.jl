### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# ╔═╡ 11111111-2222-3333-4444-555555555551
begin
    import Pkg
    package_root = dirname(@__DIR__)
    cd(package_root) do
        Pkg.activate(".")
        Pkg.develop(path="../ScienceResearch.jl")
        Pkg.instantiate()
    end
end

# ╔═╡ 11111111-2222-3333-4444-555555555552
begin
    using AspGraphsSearch
    using DataFrames
    using Plots
end

# ╔═╡ 11111111-2222-3333-4444-555555555553
md"""
# ASP fzf/rg search optimization study

Hypothesis: provider command artifacts expose enough fzf, rg, structural query, and direct-source-read behavior to find repeated search shapes, route-promotion candidates, and latency hotspots before changing ASP search algorithms.

scienceresearch-artifact: build/reports/search-optimization-summary.toml
"""

# ╔═╡ 11111111-2222-3333-4444-555555555554
begin
    artifact_root = normpath(joinpath(package_root, "..", "..", ".cache", "agent-semantic-protocol", "artifacts"))
    repo_root = normpath(joinpath(package_root, "..", ".."))
end

# ╔═╡ 11111111-2222-3333-4444-555555555555
begin
    dataset = artifact_research_dataset_from_repo(repo_root)
    optimization = artifact_search_optimization_analysis(dataset.commands)
    nothing
end

# ╔═╡ 11111111-2222-3333-4444-555555555556
default(fmt=:svg, size=(820, 420), legend=false)

# ╔═╡ 11111111-2222-3333-4444-555555555557
function markdown_table(df::DataFrame; limit::Integer=20)
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

# ╔═╡ 11111111-2222-3333-4444-555555555558
md"""
## Dataset summary

- Provider command rows: $(nrow(dataset.commands))
- Search optimization events: $(nrow(optimization.events))
- Tool summary rows: $(nrow(optimization.summary))
- Optimization graph vertices: $(length(optimization.graph.labels))
- Opportunity rows: $(nrow(optimization.opportunities))
- mtime fallback events: $(nrow(optimization.events) == 0 ? 0 : count(==("mtime"), optimization.events.time_source))
"""

# ╔═╡ 11111111-2222-3333-4444-555555555559
md"""
## Search tool taxonomy
"""

# ╔═╡ 11111111-2222-3333-4444-555555555560
markdown_table(optimization.summary; limit=25)

# ╔═╡ 11111111-2222-3333-4444-555555555561
begin
    top_tools = nrow(optimization.summary) == 0 ? DataFrame(search_tool=String[], count=Int[]) : combine(
        groupby(optimization.summary, :search_tool),
        :count => sum => :count,
    )
    sort!(top_tools, :count, rev=true)
    nrow(top_tools) == 0 ? plot(title="No search tool data") : bar(
        top_tools.search_tool,
        top_tools.count;
        title="Search optimization events by tool",
        xlabel="tool",
        ylabel="event count",
        xrotation=35,
    )
end

# ╔═╡ 11111111-2222-3333-4444-555555555562
md"""
## Route-promotion opportunities
"""

# ╔═╡ 11111111-2222-3333-4444-555555555563
markdown_table(
    select(
        optimization.opportunities,
        :category,
        :target,
        :score,
        :evidence_count,
        :recommended_action,
    );
    limit=25,
)

# ╔═╡ 11111111-2222-3333-4444-555555555564
md"""
## Search optimization graph centrality
"""

# ╔═╡ 11111111-2222-3333-4444-555555555565
begin
    centrality = select(
        first(optimization.metrics, min(30, nrow(optimization.metrics))),
        :kind,
        :name,
        :indegree,
        :outdegree,
        :degree,
        :pagerank,
    )
    markdown_table(centrality; limit=30)
end

# ╔═╡ 11111111-2222-3333-4444-555555555566
begin
    rank_plot_table = first(
        optimization.metrics[in.(optimization.metrics.kind, Ref(["tool", "query-type", "route-hint"])), :],
        min(12, nrow(optimization.metrics)),
    )
    nrow(rank_plot_table) == 0 ? plot(title="No centrality data") : bar(
        rank_plot_table.name,
        rank_plot_table.pagerank;
        title="Tool/query/route graph centrality",
        xlabel="node",
        ylabel="PageRank",
        xrotation=35,
    )
end

# ╔═╡ 11111111-2222-3333-4444-555555555567
md"""
## Event evidence
"""

# ╔═╡ 11111111-2222-3333-4444-555555555568
markdown_table(
    select(
        optimization.events,
        :relative_path,
        :search_tool,
        :query_type,
        :query_terms,
        :target_hint,
        :elapsed_ms,
        :time_source,
        :route_hint,
    );
    limit=30,
)

# ╔═╡ Cell order:
# ╠═11111111-2222-3333-4444-555555555551
# ╠═11111111-2222-3333-4444-555555555552
# ╟─11111111-2222-3333-4444-555555555553
# ╠═11111111-2222-3333-4444-555555555554
# ╠═11111111-2222-3333-4444-555555555555
# ╠═11111111-2222-3333-4444-555555555556
# ╠═11111111-2222-3333-4444-555555555557
# ╟─11111111-2222-3333-4444-555555555558
# ╟─11111111-2222-3333-4444-555555555559
# ╠═11111111-2222-3333-4444-555555555560
# ╠═11111111-2222-3333-4444-555555555561
# ╟─11111111-2222-3333-4444-555555555562
# ╠═11111111-2222-3333-4444-555555555563
# ╟─11111111-2222-3333-4444-555555555564
# ╠═11111111-2222-3333-4444-555555555565
# ╠═11111111-2222-3333-4444-555555555566
# ╟─11111111-2222-3333-4444-555555555567
# ╠═11111111-2222-3333-4444-555555555568
