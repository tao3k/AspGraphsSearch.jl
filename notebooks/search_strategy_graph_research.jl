### A Pluto.jl notebook ###
# v0.20.17

using Markdown
using InteractiveUtils

# ╔═╡ 9b2b45c8-4a9f-4f8c-8f75-23b3d1b56a01
begin
    using AspGraphsSearch
    using DataFrames
    using Graphs
    using Plots
    using Statistics
end

# ╔═╡ 59bf2f19-9cc1-41c7-9c8d-404df4106f86
md"""
# Search Strategy Graph Research

This report reconstructs search behavior from the repository artifact lake, including the root workspace artifacts and every `languages/*/.cache/agent-semantic-protocol/artifacts` directory. The goal is to study graph-router, graph-reasoning, semantic graph, lexical fallback, and structural access as one event stream.
"""

# ╔═╡ 9da2e1d7-3f0c-4d4d-a1e3-75d0a9107bb7
begin
    package_root = normpath(joinpath(@__DIR__, ".."))
    repo_root = normpath(joinpath(package_root, "..", ".."))
    dataset = artifact_research_dataset_from_repo(repo_root)
    strategy = artifact_search_strategy_analysis(dataset.commands)
    nothing
end

# ╔═╡ 5e803865-b8b3-4f0f-8d2c-31593f7232d1
function markdown_table(table::DataFrame; columns=nothing, limit::Integer=12)
    cols = columns === nothing ? names(table) : [String(column) for column in columns if String(column) in names(table)]
    isempty(cols) && return md"_No columns._"
    nrow(table) == 0 && return md"_No rows._"

    function cell(value)
        text = value === missing ? "" : string(value)
        return replace(text, "|" => "\\|", "\n" => " ")
    end

    view = first(table[:, cols], min(limit, nrow(table)))
    lines = String[
        "|" * join(cols, "|") * "|",
        "|" * join(fill("---", length(cols)), "|") * "|",
    ]
    for row in eachrow(view)
        push!(lines, "|" * join((cell(row[column]) for column in cols), "|") * "|")
    end
    nrow(table) > limit && push!(lines, "|...|$(nrow(table) - limit) more rows|")
    return Markdown.parse(join(lines, "\n"))
end

# ╔═╡ 2f09b73d-66ad-4804-9e48-d456da42a52a
md"""
## Artifact Lake Coverage

The analyzer now treats each artifact root as a scope. This prevents same-name JSON files from different language package caches from collapsing into one graph node.
"""

# ╔═╡ 284bb7d5-717d-41e3-bba1-5c074042d6e5
markdown_table(
    dataset.artifact_roots;
    columns=[:artifact_scope, :artifact_root_relative, :json_file_count],
    limit=30,
)

# ╔═╡ ec036022-0f9b-4f5f-9b6e-94770c06152f
begin
    scope_inventory = nrow(dataset.inventory) == 0 ?
        DataFrame(artifact_scope=String[], json_files=Int[]) :
        combine(groupby(dataset.inventory, :artifact_scope), nrow => :json_files)
    scope_commands = nrow(dataset.commands) == 0 ?
        DataFrame(artifact_scope=String[], provider_commands=Int[]) :
        combine(groupby(dataset.commands, :artifact_scope), nrow => :provider_commands)
    scope_packets = nrow(dataset.packets) == 0 ?
        DataFrame(artifact_scope=String[], search_packets=Int[]) :
        combine(groupby(dataset.packets, :artifact_scope), nrow => :search_packets)
    scope_coverage = outerjoin(scope_inventory, scope_commands, scope_packets; on=:artifact_scope)
    for column in [:json_files, :provider_commands, :search_packets]
        column in propertynames(scope_coverage) && replace!(scope_coverage[!, column], missing => 0)
    end
    sort!(scope_coverage, :artifact_scope)
    nothing
end

# ╔═╡ 277dcfdd-2951-4086-90a4-dbe3af6641ed
markdown_table(scope_coverage; limit=40)

# ╔═╡ 191a9077-ddab-467a-8f4e-344f48d84016
md"""
## Strategy Taxonomy

Strategies are reconstructed from provider command argv, method, operation, query type, route hint, and target hint. The taxonomy keeps graph strategies separate from lexical search and structural access so that fallback behavior is visible.
"""

# ╔═╡ d7e39199-201d-4c13-8d8f-fb199d43296d
markdown_table(
    strategy.summary;
    columns=[:artifact_scope, :strategy_family, :strategy, :events, :distinct_normalized_keys, :repeat_pressure, :mean_elapsed_ms, :max_elapsed_ms],
    limit=30,
)

# ╔═╡ 3ea45270-cb09-49a7-b3ff-04e939753e69
begin
    top_strategies = first(strategy.summary, min(15, nrow(strategy.summary)))
    strategy_plot = nrow(top_strategies) == 0 ?
        plot(title="No strategy events", legend=false) :
        bar(
            top_strategies.strategy,
            top_strategies.events;
            group=top_strategies.strategy_family,
            xlabel="strategy",
            ylabel="events",
            title="Top reconstructed search strategies",
            xrotation=35,
            legend=:topright,
        )
    nothing
end

# ╔═╡ 7f9947d5-05a8-4a14-95d0-03e38e849fed
strategy_plot

# ╔═╡ f3141c14-c73d-4d0a-b3c9-457df7415d28
md"""
## Graph Strategy Evidence

Graph-router, graph-reasoning, and semantic graph events should have enough metadata to explain candidate generation, routing choice, confidence, and fallback reason. When the artifact stream lacks those fields, the analyzer records the gap as a research opportunity instead of hiding it.
"""

# ╔═╡ 8fc942b1-9c0d-44e9-a236-4691143305d7
begin
    graph_strategy_names = Set(["graph-router", "graph-reasoning", "semantic-graph"])
    graph_strategy_events = nrow(strategy.events) == 0 ?
        strategy.events :
        strategy.events[[event.strategy in graph_strategy_names for event in eachrow(strategy.events)], :]
    nothing
end

# ╔═╡ 9de94954-2676-4dc8-b8d4-6b081c5d7bb4
markdown_table(
    graph_strategy_events;
    columns=[:artifact_scope, :strategy, :search_tool, :query_type, :query_terms, :route_hint, :elapsed_ms, :relative_path],
    limit=25,
)

# ╔═╡ c1412299-4a5f-47fa-a398-c91204dba315
markdown_table(
    strategy.opportunities;
    columns=[:category, :target, :score, :evidence_count, :evidence, :recommended_action],
    limit=30,
)

# ╔═╡ dfd0a81d-f07c-4df7-9728-cd01526caf1f
md"""
## Reconstructed Strategy Flow

The transition table approximates the agent-triggered strategy flow within each artifact scope. Large repeated transitions or graph-to-lexical fallback transitions are candidates for protocol instrumentation and router evaluation.
"""

# ╔═╡ 5630d487-f2b8-446f-99cd-f3de5383522b
markdown_table(
    strategy.transitions;
    columns=[:artifact_scope, :from_strategy, :to_strategy, :transitions, :mean_delta_ms, :max_delta_ms],
    limit=30,
)

# ╔═╡ a3d2c0a1-8d74-49cd-a0a6-409cda6c0b3b
function strategy_centrality_table(strategy_graph::ArtifactSearchOptimizationGraph; limit::Integer=25)
    graph = strategy_graph.graph
    nv(graph) == 0 && return DataFrame(label=String[], pagerank=Float64[], degree=Int[])
    ranks = Graphs.pagerank(graph)
    centrality = DataFrame(
        label = strategy_graph.labels,
        pagerank = ranks,
        degree = [indegree(graph, vertex) + outdegree(graph, vertex) for vertex in vertices(graph)],
    )
    centrality = centrality[[occursin("strategy:", row.label) || occursin("scope:", row.label) || occursin("route-hint:", row.label) for row in eachrow(centrality)], :]
    sort!(centrality, [:pagerank, :degree], rev=true)
    return first(centrality, min(limit, nrow(centrality)))
end

# ╔═╡ f5189f6f-373c-4589-b0c1-62e08b4d9eca
md"""
## Graph Metrics

Centrality here is not a quality score. It is a way to find which scopes, strategies, and route hints dominate the reconstructed event graph and therefore deserve deeper algorithmic inspection.
"""

# ╔═╡ 4b64daf8-5341-4e86-aec3-08ff011f38d5
markdown_table(strategy_centrality_table(strategy.graph); limit=25)

# ╔═╡ 5b7a9b6f-62e9-49f8-b4a8-bb34e57c00ef
begin
    graph_metrics = DataFrame(
        metric = ["events", "vertices", "edges", "components"],
        value = [
            nrow(strategy.events),
            nv(strategy.graph.graph),
            ne(strategy.graph.graph),
            nv(strategy.graph.graph) == 0 ? 0 : length(weakly_connected_components(strategy.graph.graph)),
        ],
    )
    nothing
end

# ╔═╡ 7a5c0ab0-9384-4ea2-9283-0db4ff3c1519
markdown_table(graph_metrics)

# ╔═╡ b15ef4f2-62f9-4137-81e0-43e7b8c2a397
md"""
## Research Questions To Carry Forward

1. Does graph-router reduce repeated lexical search pressure for the same normalized query key?
2. Do graph-reasoning events expose enough candidate and edge evidence to explain why a route was chosen?
3. Which language scopes lack graph strategy telemetry even though they have search activity?
4. Which graph-to-lexical fallback transitions are useful fallbacks, and which indicate missing graph facts or poor route ranking?
5. What fields must be added to artifacts so ScienceResearch.jl experiments can compare router choices, candidate graph shape, latency, and downstream command count?
"""

# ╔═╡ Cell order:
# ╠═9b2b45c8-4a9f-4f8c-8f75-23b3d1b56a01
# ╟─59bf2f19-9cc1-41c7-9c8d-404df4106f86
# ╠═9da2e1d7-3f0c-4d4d-a1e3-75d0a9107bb7
# ╠═5e803865-b8b3-4f0f-8d2c-31593f7232d1
# ╟─2f09b73d-66ad-4804-9e48-d456da42a52a
# ╠═284bb7d5-717d-41e3-bba1-5c074042d6e5
# ╠═ec036022-0f9b-4f5f-9b6e-94770c06152f
# ╠═277dcfdd-2951-4086-90a4-dbe3af6641ed
# ╟─191a9077-ddab-467a-8f4e-344f48d84016
# ╠═d7e39199-201d-4c13-8d8f-fb199d43296d
# ╠═3ea45270-cb09-49a7-b3ff-04e939753e69
# ╠═7f9947d5-05a8-4a14-95d0-03e38e849fed
# ╟─f3141c14-c73d-4d0a-b3c9-457df7415d28
# ╠═8fc942b1-9c0d-44e9-a236-4691143305d7
# ╠═9de94954-2676-4dc8-b8d4-6b081c5d7bb4
# ╠═c1412299-4a5f-47fa-a398-c91204dba315
# ╟─dfd0a81d-f07c-4df7-9728-cd01526caf1f
# ╠═5630d487-f2b8-446f-99cd-f3de5383522b
# ╠═a3d2c0a1-8d74-49cd-a0a6-409cda6c0b3b
# ╟─f5189f6f-373c-4589-b0c1-62e08b4d9eca
# ╠═4b64daf8-5341-4e86-aec3-08ff011f38d5
# ╠═5b7a9b6f-62e9-49f8-b4a8-bb34e57c00ef
# ╠═7a5c0ab0-9384-4ea2-9283-0db4ff3c1519
# ╟─b15ef4f2-62f9-4137-81e0-43e7b8c2a397
