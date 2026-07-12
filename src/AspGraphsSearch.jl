module AspGraphsSearch

using DataFrames
using Dates
using Graphs
using JSON
using ScienceResearch
using Statistics

include("artifact_research.jl")
include("search_optimization.jl")

export SearchCommandRecord,
    ArtifactSearchGraph,
    ArtifactActionFlowGraph,
    ArtifactSearchOptimizationGraph,
    collect_search_commands,
    artifact_json_inventory,
    artifact_search_packet_table,
    artifact_provider_command_table,
    artifact_discover_roots,
    artifact_root_table,
    artifact_action_taxonomy,
    artifact_phase_table,
    artifact_time_gap_table,
    artifact_action_flow_graph,
    artifact_action_flow_metrics,
    artifact_research_dataset,
    artifact_research_dataset_from_repo,
    artifact_research_dataset_from_roots,
    artifact_search_tool_table,
    artifact_search_tool_summary,
    artifact_search_optimization_graph,
    artifact_search_optimization_metrics,
    artifact_search_optimization_opportunities,
    artifact_search_optimization_analysis,
    artifact_lexical_algorithm_analysis,
    artifact_rg_algorithm_analysis,
    artifact_search_strategy_table,
    artifact_search_strategy_summary,
    artifact_search_strategy_transitions,
    artifact_search_strategy_graph,
    artifact_search_strategy_opportunities,
    artifact_search_strategy_analysis,
    artifact_command_table,
    search_command_graph,
    artifact_graph_metrics,
    personalized_artifact_rank,
    artifact_improvement_opportunities,
    artifact_algorithm_analysis,
    summarize_search_graph,
    research_experiment_spec

const ASP_FACADES = Set([
    "gerbil-scheme",
    "julia",
    "md",
    "org",
    "python",
    "rust",
    "typescript",
])

const SEARCH_VERBS = Set(["query", "search"])
const COMMAND_RE = r"\basp\s+(?:gerbil-scheme|julia|md|org|python|rust|typescript|query|search)[^\n\r`|;]*"
const TEXT_EXTENSIONS = Set([
    ".json",
    ".jsonl",
    ".log",
    ".md",
    ".org",
    ".out",
    ".txt",
])

struct SearchCommandRecord
    source_path::String
    command::String
    language::Union{Nothing,String}
    verb::String
    args::Vector{String}
end

struct ArtifactSearchGraph
    graph::SimpleDiGraph{Int}
    labels::Vector{String}
    records::Vector{SearchCommandRecord}
end

function collect_search_commands(root::AbstractString; max_file_bytes::Integer=2_000_000)
    records = SearchCommandRecord[]
    isdir(root) || return records

    for (dir, dirs, files) in walkdir(root)
        filter!(name -> !startswith(name, ".git") && name != "archives", dirs)
        for file in files
            path = joinpath(dir, file)
            should_scan(path, max_file_bytes) || continue
            text = try
                read(path, String)
            catch
                continue
            end

            rel = relpath(path, root)
            for m in eachmatch(COMMAND_RE, text)
                record = parse_search_command(rel, strip(m.match))
                record === nothing || push!(records, record)
            end
        end
    end

    return records
end

function should_scan(path::AbstractString, max_file_bytes::Integer)
    _, ext = splitext(path)
    ext in TEXT_EXTENSIONS || return false
    stat(path).size <= max_file_bytes
end

function parse_search_command(source_path::AbstractString, command::AbstractString)
    parts = split(command)
    length(parts) >= 2 || return nothing
    parts[1] == "asp" || return nothing

    if parts[2] in ASP_FACADES && length(parts) >= 3 && parts[3] in SEARCH_VERBS
        return SearchCommandRecord(
            String(source_path),
            String(command),
            parts[2],
            parts[3],
            String.(parts[4:end]),
        )
    end

    if parts[2] in SEARCH_VERBS
        return SearchCommandRecord(
            String(source_path),
            String(command),
            language_from_args(parts[3:end]),
            parts[2],
            String.(parts[3:end]),
        )
    end

    return nothing
end

function language_from_args(args)
    for (index, arg) in pairs(args)
        if arg == "--language" && index < length(args)
            return String(args[index + 1])
        elseif startswith(arg, "--language=")
            return String(last(split(arg, "=", limit=2)))
        end
    end
    return nothing
end

function search_command_graph(records::Vector{SearchCommandRecord})
    graph = SimpleDiGraph(0)
    labels = String[]
    index = Dict{String,Int}()

    vertex(label) = get!(index, label) do
        add_vertex!(graph)
        push!(labels, label)
        return length(labels)
    end

    for record in records
        file_id = vertex("file:" * record.source_path)
        command_id = vertex("command:" * command_signature(record))
        verb_id = vertex("verb:" * record.verb)
        operation_id = vertex("operation:" * command_operation(record))
        add_edge!(graph, file_id, command_id)
        add_edge!(graph, command_id, verb_id)
        add_edge!(graph, command_id, operation_id)

        if record.language !== nothing
            language_id = vertex("language:" * record.language)
            add_edge!(graph, command_id, language_id)
        end
    end

    return ArtifactSearchGraph(graph, labels, records)
end

function command_signature(record::SearchCommandRecord)
    language = record.language === nothing ? "<generic>" : record.language
    return join(("asp", language, record.verb), " ")
end

function command_operation(record::SearchCommandRecord)
    record.verb == "query" && return "query"

    skip_next = false
    for arg in record.args
        if skip_next
            skip_next = false
            continue
        elseif arg == "--language"
            skip_next = true
            continue
        elseif startswith(arg, "--language=") || startswith(arg, "-")
            continue
        end
        return clean_command_token(arg)
    end

    return record.verb
end

function clean_command_token(arg::AbstractString)
    token = replace(String(arg), r"^[`'\"(\[]+" => "")
    token = replace(token, r"[`'\"\),.;\]]+$" => "")
    return isempty(token) ? String(arg) : token
end

function artifact_command_table(records::Vector{SearchCommandRecord})
    return DataFrame(
        source_path = [record.source_path for record in records],
        command = [record.command for record in records],
        language = [something(record.language, "<generic>") for record in records],
        verb = [record.verb for record in records],
        operation = [command_operation(record) for record in records],
        arg_count = [length(record.args) for record in records],
        signature = [command_signature(record) for record in records],
    )
end

function summarize_search_graph(artifact_graph::ArtifactSearchGraph)
    language_counts = count_by(record -> something(record.language, "<generic>"), artifact_graph.records)
    verb_counts = count_by(record -> record.verb, artifact_graph.records)
    command_counts = count_by(command_signature, artifact_graph.records)

    return (;
        record_count = length(artifact_graph.records),
        vertex_count = nv(artifact_graph.graph),
        edge_count = ne(artifact_graph.graph),
        languages = language_counts,
        verbs = verb_counts,
        commands = command_counts,
    )
end

function count_by(keyfn, values)
    counts = Dict{String,Int}()
    for value in values
        key = String(keyfn(value))
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

function artifact_graph_metrics(artifact_graph::ArtifactSearchGraph)
    graph = artifact_graph.graph
    vertex_count = nv(graph)
    vertex_count == 0 && return DataFrame(
        vertex = Int[],
        label = String[],
        kind = String[],
        name = String[],
        indegree = Int[],
        outdegree = Int[],
        degree = Int[],
        pagerank = Float64[],
        component = Int[],
    )

    components = weakly_connected_components(graph)
    component_ids = zeros(Int, vertex_count)
    for (component_id, component) in pairs(components)
        for vertex_id in component
            component_ids[vertex_id] = component_id
        end
    end

    ranks = pagerank(graph)
    kinds = String[]
    names = String[]
    for label in artifact_graph.labels
        kind, name = label_parts(label)
        push!(kinds, kind)
        push!(names, name)
    end

    return DataFrame(
        vertex = collect(1:vertex_count),
        label = artifact_graph.labels,
        kind = kinds,
        name = names,
        indegree = [indegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        outdegree = [outdegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        degree = [indegree(graph, vertex_id) + outdegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        pagerank = ranks,
        component = component_ids,
    )
end

function label_parts(label::AbstractString)
    parts = split(label, ":", limit=2)
    length(parts) == 2 || return ("unknown", String(label))
    return (String(parts[1]), String(parts[2]))
end

function personalized_artifact_rank(
    artifact_graph::ArtifactSearchGraph;
    seed_prefixes=("operation:pipe", "operation:prime", "verb:search"),
    damping::Float64=0.85,
    max_iter::Integer=100,
    tolerance::Float64=1.0e-8,
)
    graph = artifact_graph.graph
    vertex_count = nv(graph)
    vertex_count == 0 && return DataFrame(
        vertex = Int[],
        label = String[],
        kind = String[],
        name = String[],
        indegree = Int[],
        outdegree = Int[],
        degree = Int[],
        pagerank = Float64[],
        component = Int[],
        ppr_score = Float64[],
    )

    seeds = [
        vertex_id for (vertex_id, label) in pairs(artifact_graph.labels)
        if any(seed -> seed_label_matches(label, seed), seed_prefixes)
    ]
    isempty(seeds) && append!(seeds, 1:vertex_count)

    teleport = zeros(Float64, vertex_count)
    for seed in seeds
        teleport[seed] += 1.0 / length(seeds)
    end

    scores = copy(teleport)
    for _ in 1:max_iter
        next_scores = (1.0 - damping) .* teleport
        dangling_mass = 0.0
        for vertex_id in 1:vertex_count
            neighbors = outneighbors(graph, vertex_id)
            if isempty(neighbors)
                dangling_mass += scores[vertex_id]
            else
                contribution = damping * scores[vertex_id] / length(neighbors)
                for neighbor in neighbors
                    next_scores[neighbor] += contribution
                end
            end
        end
        next_scores .+= damping * dangling_mass .* teleport
        if sum(abs.(next_scores .- scores)) <= tolerance
            scores = next_scores
            break
        end
        scores = next_scores
    end

    metrics = artifact_graph_metrics(artifact_graph)
    metrics[!, :ppr_score] = scores
    sort!(metrics, [:ppr_score, :pagerank], rev=[true, true])
    return metrics
end

function seed_label_matches(label::AbstractString, seed::AbstractString)
    label == seed && return true
    endswith(seed, ":") && return startswith(label, seed)
    return false
end

function artifact_improvement_opportunities(artifact_graph::ArtifactSearchGraph; top_n::Integer=12)
    records = artifact_graph.records
    total = max(length(records), 1)
    opportunities = DataFrame(
        category = String[],
        target = String[],
        score = Float64[],
        evidence_count = Int[],
        reason = String[],
        recommended_action = String[],
    )

    add_opportunity!(opportunities, "missing-language-facade", "<generic>", count(record -> record.language === nothing, records), total)

    for (operation, count) in count_by(command_operation, records)
        if count >= 2 || operation in ("pipe", "prime", "lexical", "query", "deps", "owner")
            add_opportunity!(
                opportunities,
                "operation-hotspot",
                operation,
                count,
                total;
                reason = "operation appears in artifact search/query command traces",
                recommended_action = operation_recommendation(operation),
            )
        end
    end

    for (signature, count) in count_by(command_signature, records)
        if count >= 2
            add_opportunity!(
                opportunities,
                "repeat-command-shape",
                signature,
                count,
                total;
                reason = "same command signature repeats across artifacts",
                recommended_action = "Promote the repeated command shape into clearer first-action guidance or a cached frontier.",
            )
        end
    end

    for (source_path, count) in count_by(record -> record.source_path, records)
        if count >= 3
            add_opportunity!(
                opportunities,
                "artifact-file-hub",
                source_path,
                count,
                total;
                reason = "artifact file contains many ASP search/query commands",
                recommended_action = "Inspect this artifact as a concentrated workflow trace before changing provider behavior.",
            )
        end
    end

    rank = personalized_artifact_rank(artifact_graph)
    for row in eachrow(first(rank, min(8, nrow(rank))))
        row.kind in ("operation", "language", "command") || continue
        add_opportunity!(
            opportunities,
            "ppr-hotspot",
            row.label,
            max(1, round(Int, row.degree)),
            total;
            score = row.ppr_score,
            reason = "personalized rank from search/pipe/prime seeds surfaced this node",
            recommended_action = "Use this node as the next focused analysis seed.",
        )
    end

    nrow(opportunities) == 0 && return opportunities
    sort!(opportunities, [:score, :evidence_count], rev=[true, true])
    return first(opportunities, min(top_n, nrow(opportunities)))
end

function add_opportunity!(
    opportunities::DataFrame,
    category::AbstractString,
    target::AbstractString,
    count::Integer,
    total::Integer;
    score::Union{Nothing,Float64}=nothing,
    reason::AbstractString = "artifact search/query command evidence",
    recommended_action::AbstractString = "Review the repeated pattern and decide whether provider guidance, docs, or cache behavior should change.",
)
    count <= 0 && return opportunities
    computed_score = score === nothing ? min(1.0, count / max(total, 1)) : score
    push!(
        opportunities,
        (
            category = String(category),
            target = String(target),
            score = computed_score,
            evidence_count = Int(count),
            reason = String(reason),
            recommended_action = String(recommended_action),
        ),
    )
    return opportunities
end

function operation_recommendation(operation::AbstractString)
    operation == "pipe" && return "Reduce repeated query-pack refinement by improving first search guidance and nextCommand specificity."
    operation == "prime" && return "Keep prime as owner-map discovery only; add stronger owner/symbol preconditions when repeated."
    operation == "lexical" && return "Promote broad fuzzy recovery into typed owner/dependency/frontier routes."
    operation == "deps" && return "Document dependency-topology routes as the preferred first command for package questions."
    operation == "owner" && return "Check whether owner-items output gives enough next-action detail to avoid manual source scans."
    operation == "query" && return "Prefer exact owner or selector identity before query-code reads."
    return "Inspect repeated operation usage for missing guidance, cache, or typed-frontier opportunities."
end

function artifact_algorithm_analysis(records::Vector{SearchCommandRecord}; root::AbstractString="artifacts", top_n::Integer=12)
    artifact_graph = search_command_graph(records)
    return (;
        summary = summarize_search_graph(artifact_graph),
        commands = artifact_command_table(records),
        graph_metrics = artifact_graph_metrics(artifact_graph),
        personalized_rank = personalized_artifact_rank(artifact_graph),
        opportunities = artifact_improvement_opportunities(artifact_graph; top_n),
        experiment = research_experiment_spec(records; root),
    )
end

function research_experiment_spec(records::Vector{SearchCommandRecord}; root::AbstractString="artifacts")
    dataset = DatasetSpec(;
        id = "asp-artifacts-search-commands",
        description = "ASP artifact search/query command records extracted from $(root).",
        source = String(root),
        row_count = length(records),
    )
    workload = WorkloadSpec(;
        id = "search-command-graph",
        description = "Build a command/language/file graph for ASP search/query workflow analysis.",
        scale = Dict("records" => length(records)),
        budget = Dict("latency_ms" => 1_000.0),
    )

    return ExperimentSpec(;
        id = "asp-artifacts-search-command-analysis",
        title = "ASP Artifacts Search Command Analysis",
        dataset,
        workload,
        idea = "Use Graphs.jl and ScienceResearch.jl to inspect search/query command patterns before optimizing ASP code and docs search.",
        metrics = [
            MetricSpec(; name = "record_count"),
            MetricSpec(; name = "vertex_count"),
            MetricSpec(; name = "edge_count"),
            MetricSpec(; name = "opportunity_count"),
        ],
    )
end

end
