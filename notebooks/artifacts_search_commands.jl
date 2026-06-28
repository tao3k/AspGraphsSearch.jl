### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# ╔═╡ 11111111-1111-1111-1111-111111111111
begin
    import Pkg
    package_root = dirname(@__DIR__)
    cd(package_root) do
        Pkg.activate(".")
        Pkg.develop(path="../ScienceResearch.jl")
        Pkg.instantiate()
    end
end

# ╔═╡ 22222222-2222-2222-2222-222222222222
begin
    using AspGraphsSearch
    using DataFrames
    using Plots
end

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"""
# ASP artifacts search/query DataScience study

Hypothesis: JSON artifacts under `.cache/agent-semantic-protocol/artifacts` contain enough command, packet, language, method, latency, and weak-time evidence to reconstruct agent-triggered search/query flow and identify protocol/documentation search improvements.

scienceresearch-artifact: build/reports/artifacts-search-command-summary.toml
"""

# ╔═╡ 44444444-4444-4444-4444-444444444444
begin
    repo_root = normpath(joinpath(package_root, "..", ".."))
    artifact_roots = artifact_discover_roots(repo_root)
end

# ╔═╡ 55555555-5555-5555-5555-555555555555
begin
    dataset = artifact_research_dataset_from_repo(repo_root)
    nothing
end

# ╔═╡ 56666666-6666-6666-6666-666666666661
begin
    records = SearchCommandRecord[]
    for root in artifact_roots
        append!(records, collect_search_commands(root))
    end
    nothing
end

# ╔═╡ 66666666-6666-6666-6666-666666666666
begin
    command_graph = search_command_graph(records)
    nothing
end

# ╔═╡ 77777777-7777-7777-7777-777777777777
begin
    baseline = artifact_algorithm_analysis(records; root=repo_root)
    nothing
end

# ╔═╡ 7aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1
default(fmt=:svg, size=(820, 420), legend=false)

# ╔═╡ 81111111-1111-1111-1111-111111111111
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

# ╔═╡ 88888888-8888-8888-8888-888888888888
begin
    research_spec = research_experiment_spec(records; root=repo_root)
    nothing
end

# ╔═╡ 99999999-9999-9999-9999-999999999999
md"""
## Dataset summary

- JSON artifacts: $(nrow(dataset.inventory))
- Search/query packets: $(nrow(dataset.packets))
- Provider command rows: $(nrow(dataset.commands))
- Event-time phases: $(nrow(dataset.phases))
- Time-source gap rows: $(nrow(dataset.time_gaps))
- JSON-timed provider commands: $(nrow(dataset.commands) == 0 ? 0 : count(!=("mtime"), dataset.commands.time_source))
- Flow graph vertices: $(length(dataset.flow.labels))
- Flow graph metric rows: $(nrow(dataset.flow_metrics))
- Legacy command records from text artifacts: $(baseline.summary.record_count)
"""

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
md"""
## Artifact JSON inventory
"""

# ╔═╡ a1111111-1111-1111-1111-111111111111
begin
    schema_counts = nrow(dataset.inventory) == 0 ? DataFrame(schema_id=String[], count=Int[]) : sort(
        combine(groupby(dataset.inventory, :schema_id), nrow => :count),
        :count;
        rev=true,
    )
    nothing
end

# ╔═╡ a2222222-2222-2222-2222-222222222222
markdown_table(schema_counts; limit=20)

# ╔═╡ a3333333-3333-3333-3333-333333333333
md"""
## Search/query packet taxonomy
"""

# ╔═╡ a4444444-4444-4444-4444-444444444444
begin
    method_counts = nrow(dataset.packets) == 0 ? DataFrame(method=String[], count=Int[]) : sort(
        combine(groupby(dataset.packets, :method), nrow => :count),
        :count;
        rev=true,
    )
    nothing
end

# ╔═╡ a5555555-5555-5555-5555-555555555555
markdown_table(method_counts; limit=20)

# ╔═╡ a6666666-6666-6666-6666-666666666666
begin
    top_methods = first(method_counts, min(12, nrow(method_counts)))
    nrow(top_methods) == 0 ? plot(title="No packet method data") : bar(
        top_methods.method,
        top_methods.count;
        title="Search/query packet methods",
        xlabel="method",
        ylabel="packet count",
        xrotation=35,
    )
end

# ╔═╡ b1111111-1111-1111-1111-111111111111
md"""
## Provider command language and operation taxonomy
"""

# ╔═╡ b2222222-2222-2222-2222-222222222222
begin
    language_counts = nrow(dataset.commands) == 0 ? DataFrame(language=String[], count=Int[]) : sort(
        combine(groupby(dataset.commands, :language), nrow => :count),
        :count;
        rev=true,
    )
    nothing
end

# ╔═╡ b3333333-3333-3333-3333-333333333333
markdown_table(language_counts; limit=20)

# ╔═╡ b4444444-4444-4444-4444-444444444444
begin
    top_languages = first(language_counts, min(12, nrow(language_counts)))
    nrow(top_languages) == 0 ? plot(title="No provider command language data") : bar(
        top_languages.language,
        top_languages.count;
        title="Provider command languages",
        xlabel="language",
        ylabel="command count",
        xrotation=35,
    )
end

# ╔═╡ b5555555-5555-5555-5555-555555555555
markdown_table(dataset.taxonomy; limit=25)

# ╔═╡ c1111111-1111-1111-1111-111111111111
md"""
## Artifact event-time completeness

Event-time analysis prefers JSON timestamps from artifacts and provider commands. Rows marked `mtime` are fallback evidence and identify instrumentation gaps.
"""

# ╔═╡ c2111111-1111-1111-1111-111111111111
markdown_table(dataset.time_gaps; limit=30)

# ╔═╡ c2111111-1111-1111-1111-111111111112
md"""
## Event-time action phases

Phases are reconstructed from explicit JSON event time when present, with file modification time only as a fallback.
"""

# ╔═╡ c2222222-2222-2222-2222-222222222222
markdown_table(dataset.phases; limit=20)

# ╔═╡ c3333333-3333-3333-3333-333333333333
begin
    nrow(dataset.phases) == 0 ? plot(title="No phase data") : bar(
        string.(dataset.phases.event_phase),
        dataset.phases.command_count;
        title="Provider commands by event-time phase",
        xlabel="event phase",
        ylabel="command count",
    )
end

# ╔═╡ d1111111-1111-1111-1111-111111111111
md"""
## Reconstructed action-flow graph
"""

# ╔═╡ d2222222-2222-2222-2222-222222222222
markdown_table(
    select(dataset.flow_metrics, :kind, :name, :indegree, :outdegree, :degree, :pagerank),
    limit=25,
)

# ╔═╡ d3333333-3333-3333-3333-333333333333
md"""
## Baseline text command extraction

This keeps the previous text-artifact extractor as a baseline next to the JSON-first analysis.
"""

# ╔═╡ d4444444-4444-4444-4444-444444444444
begin
    opportunity_table = select(
        baseline.opportunities,
        :category,
        :target,
        :score,
        :evidence_count,
        :recommended_action,
    )
    nothing
end

# ╔═╡ d5555555-5555-5555-5555-555555555555
begin
    rank_table = select(
        first(baseline.personalized_rank, min(15, nrow(baseline.personalized_rank))),
        :kind,
        :name,
        :degree,
        :pagerank,
        :ppr_score,
    )
    nothing
end

# ╔═╡ d5555555-5555-5555-5555-555555555556
markdown_table(opportunity_table; limit=20)

# ╔═╡ d5555555-5555-5555-5555-555555555557
markdown_table(rank_table; limit=15)

# ╔═╡ d6666666-6666-6666-6666-666666666666
begin
    rank_plot_table = first(rank_table, min(10, nrow(rank_table)))
    nrow(rank_plot_table) == 0 ? plot(title="No baseline rank data") : bar(
        rank_plot_table.name,
        rank_plot_table.ppr_score;
        title="Legacy text-command personalized rank",
        xlabel="node",
        ylabel="PPR score",
        xrotation=35,
    )
end

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-111111111111
# ╠═22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╠═44444444-4444-4444-4444-444444444444
# ╠═55555555-5555-5555-5555-555555555555
# ╠═56666666-6666-6666-6666-666666666661
# ╠═66666666-6666-6666-6666-666666666666
# ╠═77777777-7777-7777-7777-777777777777
# ╠═7aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1
# ╠═81111111-1111-1111-1111-111111111111
# ╠═88888888-8888-8888-8888-888888888888
# ╟─99999999-9999-9999-9999-999999999999
# ╟─aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╠═a1111111-1111-1111-1111-111111111111
# ╠═a2222222-2222-2222-2222-222222222222
# ╟─a3333333-3333-3333-3333-333333333333
# ╠═a4444444-4444-4444-4444-444444444444
# ╠═a5555555-5555-5555-5555-555555555555
# ╠═a6666666-6666-6666-6666-666666666666
# ╟─b1111111-1111-1111-1111-111111111111
# ╠═b2222222-2222-2222-2222-222222222222
# ╠═b3333333-3333-3333-3333-333333333333
# ╠═b4444444-4444-4444-4444-444444444444
# ╠═b5555555-5555-5555-5555-555555555555
# ╟─c1111111-1111-1111-1111-111111111111
# ╠═c2111111-1111-1111-1111-111111111111
# ╟─c2111111-1111-1111-1111-111111111112
# ╠═c2222222-2222-2222-2222-222222222222
# ╠═c3333333-3333-3333-3333-333333333333
# ╟─d1111111-1111-1111-1111-111111111111
# ╠═d2222222-2222-2222-2222-222222222222
# ╟─d3333333-3333-3333-3333-333333333333
# ╠═d4444444-4444-4444-4444-444444444444
# ╠═d5555555-5555-5555-5555-555555555555
# ╠═d5555555-5555-5555-5555-555555555556
# ╠═d5555555-5555-5555-5555-555555555557
# ╠═d6666666-6666-6666-6666-666666666666
