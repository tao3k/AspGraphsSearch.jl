struct ArtifactSearchOptimizationGraph
    graph::SimpleDiGraph
    labels::Vector{String}
    events::DataFrame
end

const SEARCH_OPTIMIZATION_TOOLS = Set([
    "lexical",
    "rg",
    "prime",
    "owner-index",
    "dependency-index",
    "structural-query",
    "direct-source-read",
    "generic-search",
    "generic-query",
])

function artifact_search_tool_table(commands::DataFrame)
    rows = DataFrame(
        event_index = Int[],
        artifact_scope = String[],
        artifact_root_relative = String[],
        relative_path = String[],
        event_phase = Int[],
        event_time = DateTime[],
        time_source = String[],
        language = String[],
        provider = String[],
        method = String[],
        operation = String[],
        command_family = String[],
        search_tool = String[],
        query_type = String[],
        query_terms = String[],
        target_hint = String[],
        route_hint = String[],
        elapsed_ms = Union{Missing,Int}[],
        exit_code = Union{Missing,Int}[],
        stdout_bytes = Union{Missing,Int}[],
        stderr_bytes = Union{Missing,Int}[],
        total_bytes = Union{Missing,Int}[],
        normalized_key = String[],
    )
    nrow(commands) == 0 && return rows

    for (event_index, row) in enumerate(eachrow(commands))
        argv = artifact_command_argv(row)
        method = artifact_row_string(row, :method)
        operation = artifact_row_string(row, :operation)
        command_family = artifact_row_string(row, :command_family)
        tool = artifact_search_tool(argv, method, operation, command_family)
        tool in SEARCH_OPTIMIZATION_TOOLS || continue

        query_type = artifact_search_query_type(argv, tool, method, operation)
        query_terms = artifact_search_query_terms(argv, tool)
        target_hint = artifact_search_target_hint(argv, tool)
        route_hint = artifact_route_hint(tool, query_type, target_hint)
        stdout_bytes = artifact_row_int(row, :stdout_bytes)
        stderr_bytes = artifact_row_int(row, :stderr_bytes)
        total_bytes = stdout_bytes === missing || stderr_bytes === missing ? missing : stdout_bytes + stderr_bytes
        normalized_key = artifact_normalized_search_key(
            artifact_row_string(row, :language),
            tool,
            query_type,
            query_terms,
            target_hint,
        )

        push!(rows, (
            event_index = event_index,
            artifact_scope = artifact_row_string(row, :artifact_scope),
            artifact_root_relative = artifact_row_string(row, :artifact_root_relative),
            relative_path = artifact_row_string(row, :relative_path),
            event_phase = artifact_row_int(row, :event_phase, 0),
            event_time = artifact_row_datetime(row, :event_time),
            time_source = artifact_row_string(row, :time_source),
            language = artifact_row_string(row, :language),
            provider = artifact_row_string(row, :provider),
            method = method,
            operation = operation,
            command_family = command_family,
            search_tool = tool,
            query_type = query_type,
            query_terms = query_terms,
            target_hint = target_hint,
            route_hint = route_hint,
            elapsed_ms = artifact_row_int(row, :elapsed_ms),
            exit_code = artifact_row_int(row, :exit_code),
            stdout_bytes = stdout_bytes,
            stderr_bytes = stderr_bytes,
            total_bytes = total_bytes,
            normalized_key = normalized_key,
        ))
    end

    sort!(rows, [:event_time, :event_index])
    return rows
end

function artifact_search_tool_summary(events::DataFrame)
    output = DataFrame(
        search_tool = String[],
        query_type = String[],
        count = Int[],
        elapsed_p50_ms = Union{Missing,Int}[],
        elapsed_p90_ms = Union{Missing,Int}[],
        elapsed_max_ms = Union{Missing,Int}[],
        stdout_total_bytes = Int[],
        stderr_total_bytes = Int[],
    )
    nrow(events) == 0 && return output

    output = combine(
        groupby(events, [:search_tool, :query_type]),
        nrow => :count,
        :elapsed_ms => artifact_median_ms => :elapsed_p50_ms,
        :elapsed_ms => artifact_p90_ms => :elapsed_p90_ms,
        :elapsed_ms => artifact_max_ms => :elapsed_max_ms,
        :stdout_bytes => artifact_sum_int => :stdout_total_bytes,
        :stderr_bytes => artifact_sum_int => :stderr_total_bytes,
    )
    sort!(output, [:count, :elapsed_p90_ms], rev=[true, true])
    return output
end

function artifact_search_optimization_graph(events::DataFrame)
    graph = SimpleDiGraph(0)
    labels = String[]
    label_to_vertex = Dict{String,Int}()

    vertex(label::AbstractString) = get!(label_to_vertex, String(label)) do
        add_vertex!(graph)
        push!(labels, String(label))
        nv(graph)
    end

    for row in eachrow(events)
        event_id = vertex("event:" * string(row.event_index))
        tool_id = vertex("tool:" * row.search_tool)
        query_type_id = vertex("query-type:" * row.query_type)
        route_id = vertex("route-hint:" * row.route_hint)
        add_edge!(graph, event_id, tool_id)
        add_edge!(graph, tool_id, query_type_id)
        add_edge!(graph, query_type_id, route_id)

        isempty(row.language) || add_edge!(graph, event_id, vertex("language:" * row.language))
        isempty(row.provider) || add_edge!(graph, event_id, vertex("provider:" * row.provider))
        isempty(row.target_hint) || add_edge!(graph, query_type_id, vertex("target:" * row.target_hint))
        isempty(row.normalized_key) || add_edge!(graph, event_id, vertex("normalized-query:" * row.normalized_key))
    end

    return ArtifactSearchOptimizationGraph(graph, labels, events)
end

function artifact_search_optimization_metrics(optimization_graph::ArtifactSearchOptimizationGraph)
    graph = optimization_graph.graph
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
    )

    ranks = pagerank(graph)
    kinds = String[]
    names = String[]
    for label in optimization_graph.labels
        kind, name = artifact_label_parts(label)
        push!(kinds, kind)
        push!(names, name)
    end

    metrics = DataFrame(
        vertex = collect(1:vertex_count),
        label = optimization_graph.labels,
        kind = kinds,
        name = names,
        indegree = [indegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        outdegree = [outdegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        degree = [indegree(graph, vertex_id) + outdegree(graph, vertex_id) for vertex_id in 1:vertex_count],
        pagerank = ranks,
    )
    sort!(metrics, [:pagerank, :degree], rev=[true, true])
    return metrics
end

function artifact_search_optimization_opportunities(events::DataFrame)
    rows = DataFrame(
        category = String[],
        target = String[],
        score = Float64[],
        evidence_count = Int[],
        evidence = String[],
        recommended_action = String[],
    )
    nrow(events) == 0 && return rows

    artifact_add_repeat_search_opportunities!(rows, events)
    artifact_add_latency_opportunities!(rows, events)
    artifact_add_tool_route_opportunities!(rows, events)
    artifact_add_time_source_opportunities!(rows, events)

    sort!(rows, [:score, :evidence_count], rev=[true, true])
    return rows
end

function artifact_search_optimization_analysis(commands::DataFrame)
    events = artifact_search_tool_table(commands)
    summary = artifact_search_tool_summary(events)
    graph = artifact_search_optimization_graph(events)
    metrics = artifact_search_optimization_metrics(graph)
    opportunities = artifact_search_optimization_opportunities(events)
    return (; events, summary, graph, metrics, opportunities)
end

artifact_nonmissing(values) = collect(skipmissing(values))

function artifact_mean_skipmissing(values)
    xs = artifact_nonmissing(values)
    isempty(xs) && return missing
    return sum(xs) / length(xs)
end

function artifact_sum_skipmissing(values)
    xs = artifact_nonmissing(values)
    isempty(xs) && return missing
    return sum(xs)
end

function artifact_max_skipmissing(values)
    xs = artifact_nonmissing(values)
    isempty(xs) && return missing
    return maximum(xs)
end

function artifact_tool_events(events::DataFrame, tool::AbstractString)
    nrow(events) == 0 && return events
    :search_tool in propertynames(events) || return events[[], :]
    return events[events.search_tool .== tool, :]
end

function artifact_tool_opportunities(opportunities::DataFrame, tool::AbstractString)
    nrow(opportunities) == 0 && return opportunities
    :search_tool in propertynames(opportunities) || return opportunities[[], :]
    return opportunities[opportunities.search_tool .== tool, :]
end

function artifact_tool_route_summary(events::DataFrame)
    columns = (
        query_type = String[],
        route_hint = String[],
        target_hint = String[],
        events = Int[],
        distinct_normalized_keys = Int[],
        repeat_pressure = Int[],
        mean_elapsed_ms = Union{Missing,Float64}[],
        max_elapsed_ms = Union{Missing,Int}[],
        total_observed_bytes = Union{Missing,Int}[],
    )
    nrow(events) == 0 && return DataFrame(columns)

    summary = combine(
        groupby(events, [:query_type, :route_hint, :target_hint]),
        nrow => :events,
        :normalized_key => (values -> length(unique(values))) => :distinct_normalized_keys,
        :normalized_key => (values -> length(values) - length(unique(values))) => :repeat_pressure,
        :elapsed_ms => artifact_mean_skipmissing => :mean_elapsed_ms,
        :elapsed_ms => artifact_max_skipmissing => :max_elapsed_ms,
        :total_bytes => artifact_sum_skipmissing => :total_observed_bytes,
    )
    sort!(summary, [:repeat_pressure, :events, :max_elapsed_ms], rev = true)
    return summary
end

function artifact_lexical_candidate_pressure(events::DataFrame)
    columns = (
        query_terms = String[],
        target_hint = String[],
        route_hint = String[],
        events = Int[],
        distinct_query_types = Int[],
        repeat_pressure = Int[],
        mean_elapsed_ms = Union{Missing,Float64}[],
        max_elapsed_ms = Union{Missing,Int}[],
    )
    nrow(events) == 0 && return DataFrame(columns)

    summary = combine(
        groupby(events, [:query_terms, :target_hint, :route_hint]),
        nrow => :events,
        :query_type => (values -> length(unique(values))) => :distinct_query_types,
        :normalized_key => (values -> length(values) - length(unique(values))) => :repeat_pressure,
        :elapsed_ms => artifact_mean_skipmissing => :mean_elapsed_ms,
        :elapsed_ms => artifact_max_skipmissing => :max_elapsed_ms,
    )
    sort!(summary, [:repeat_pressure, :events, :max_elapsed_ms], rev = true)
    return summary
end

function artifact_rg_pattern_pressure(events::DataFrame)
    columns = (
        query_terms = String[],
        target_hint = String[],
        route_hint = String[],
        events = Int[],
        distinct_languages = Int[],
        repeat_pressure = Int[],
        mean_elapsed_ms = Union{Missing,Float64}[],
        max_elapsed_ms = Union{Missing,Int}[],
        total_observed_bytes = Union{Missing,Int}[],
    )
    nrow(events) == 0 && return DataFrame(columns)

    summary = combine(
        groupby(events, [:query_terms, :target_hint, :route_hint]),
        nrow => :events,
        :language => (values -> length(unique(values))) => :distinct_languages,
        :normalized_key => (values -> length(values) - length(unique(values))) => :repeat_pressure,
        :elapsed_ms => artifact_mean_skipmissing => :mean_elapsed_ms,
        :elapsed_ms => artifact_max_skipmissing => :max_elapsed_ms,
        :total_bytes => artifact_sum_skipmissing => :total_observed_bytes,
    )
    sort!(summary, [:repeat_pressure, :events, :max_elapsed_ms], rev = true)
    return summary
end

function artifact_lexical_algorithm_notes(events::DataFrame, candidate_pressure::DataFrame, opportunities::DataFrame)
    repeated = nrow(candidate_pressure) == 0 ? 0 : sum(candidate_pressure.repeat_pressure)
    route_promotions = nrow(opportunities)
    event_count = nrow(events)

    return DataFrame(
        research_axis = [
            "candidate-pruning",
            "route-promotion",
            "interactive-repeat-cache",
        ],
        evidence_metric = [
            "events=$(event_count), repeated_normalized_queries=$(repeated)",
            "lexical_opportunities=$(route_promotions)",
            "repeat_pressure=$(repeated)",
        ],
        hypothesis = [
            "lexical should be a last-mile selector over provider-ranked candidates, not the first search primitive.",
            "Repeated lexical searches with owner/dependency/query intent can be promoted to parser-owned ASP routes.",
            "Stable query/target pairs should reuse ranked candidate sets inside a session.",
        ],
        expected_improvement = [
            "Reduce candidate set size before fuzzy scoring and lower interactive latency.",
            "Replace broad fuzzy search with deterministic owner/dependency/structural query packets.",
            "Avoid re-running equivalent fuzzy searches during agent fan-out/fan-in loops.",
        ],
        required_instrumentation = [
            "candidate_count, selected_rank, score_distribution, provider_route_before_lexical",
            "route_decision, promoted_route, rejected_route_reason",
            "session_query_hash, candidate_set_hash, cache_hit",
        ],
    )
end

function artifact_rg_algorithm_notes(events::DataFrame, pattern_pressure::DataFrame, opportunities::DataFrame)
    repeated = nrow(pattern_pressure) == 0 ? 0 : sum(pattern_pressure.repeat_pressure)
    route_promotions = nrow(opportunities)
    event_count = nrow(events)

    return DataFrame(
        research_axis = [
            "pattern-selectivity",
            "path-filter-routing",
            "structural-query-replacement",
        ],
        evidence_metric = [
            "events=$(event_count), repeated_pattern_scans=$(repeated)",
            "distinct_pattern_targets=$(nrow(pattern_pressure))",
            "rg_opportunities=$(route_promotions)",
        ],
        hypothesis = [
            "rg patterns need selectivity estimates before launching broad text scans.",
            "Path and language hints should route scans toward provider-owned indexes first.",
            "Common rg searches for symbols, owners, and dependencies can be replaced by AST/graph queries.",
        ],
        expected_improvement = [
            "Prioritize high-signal patterns and avoid scanning low-selectivity tokens across the workspace.",
            "Cut file-system traversal by narrowing language/provider/path scope before text matching.",
            "Return structured packets with stable identities instead of line-oriented text hits.",
        ],
        required_instrumentation = [
            "match_count, files_scanned, files_matched, pattern_entropy",
            "path_filter, language_filter, provider_filter, skipped_file_count",
            "query_intent, structural_selector, replacement_success",
        ],
    )
end

function artifact_lexical_algorithm_analysis(commands::DataFrame)
    overall = artifact_search_optimization_analysis(commands)
    events = artifact_tool_events(overall.events, "lexical")
    route_summary = artifact_tool_route_summary(events)
    candidate_pressure = artifact_lexical_candidate_pressure(events)
    graph = artifact_search_optimization_graph(events)
    metrics = artifact_search_optimization_metrics(graph)
    opportunities = artifact_tool_opportunities(overall.opportunities, "lexical")
    algorithm_notes = artifact_lexical_algorithm_notes(events, candidate_pressure, opportunities)
    return (; events, route_summary, candidate_pressure, graph, metrics, opportunities, algorithm_notes)
end

function artifact_rg_scope_count(events::DataFrame, count_name::Symbol)
    rows = DataFrame(:artifact_scope => String[], :language => String[], count_name => Int[])
    nrow(events) == 0 && return rows

    counts = combine(groupby(events, [:artifact_scope, :language]), nrow => count_name)
    sort!(counts, [:artifact_scope, :language])
    return counts
end

function artifact_rg_scope_coverage(
    all_events::DataFrame,
    rg_events::DataFrame,
    raw_events::DataFrame,
    pattern_events::DataFrame,
)
    rows = DataFrame(
        artifact_scope = String[],
        language = String[],
        searchable_events = Int[],
        rg_events = Int[],
        raw_rg_events = Int[],
        provider_pattern_events = Int[],
        rg_coverage_status = String[],
    )
    nrow(all_events) == 0 && return rows

    coverage = artifact_rg_scope_count(all_events, :searchable_events)
    coverage = leftjoin(coverage, artifact_rg_scope_count(rg_events, :rg_events); on = [:artifact_scope, :language])
    coverage = leftjoin(coverage, artifact_rg_scope_count(raw_events, :raw_rg_events); on = [:artifact_scope, :language])
    coverage = leftjoin(coverage, artifact_rg_scope_count(pattern_events, :provider_pattern_events); on = [:artifact_scope, :language])

    for column in [:rg_events, :raw_rg_events, :provider_pattern_events]
        coverage[!, column] = Int.(coalesce.(coverage[!, column], 0))
    end
    coverage[!, :rg_coverage_status] = [
        row.rg_events > 0 ? "rg-evidence" : "search-without-rg-evidence" for row in eachrow(coverage)
    ]

    sort!(coverage, [:rg_coverage_status, :searchable_events, :artifact_scope, :language], rev = [true, true, false, false])
    return coverage
end

function artifact_rg_coverage_opportunities(coverage::DataFrame)
    rows = DataFrame(
        category = String[],
        target = String[],
        score = Float64[],
        evidence_count = Int[],
        evidence = String[],
        recommended_action = String[],
    )
    nrow(coverage) == 0 && return rows

    for row in eachrow(coverage)
        row.rg_events == 0 || continue
        push!(
            rows,
            (
                category = "rg-coverage-gap",
                target = "$(row.artifact_scope) | $(row.language)",
                score = Float64(row.searchable_events),
                evidence_count = row.searchable_events,
                evidence = "searchable artifact events exist for this scope/language, but no raw rg or provider pattern-search evidence was emitted",
                recommended_action = "emit rg/pattern-search artifacts or classify lexical provider scans so rg notebooks can compare route quality across languages",
            ),
        )
    end

    sort!(rows, [:score, :evidence_count], rev = [true, true])
    return rows
end

function artifact_rg_algorithm_analysis(commands::DataFrame)
    overall = artifact_search_optimization_analysis(commands)
    raw_events = artifact_tool_events(overall.events, "rg")
    pattern_events = nrow(overall.events) == 0 ? overall.events : overall.events[overall.events.query_type .== "pattern-search", :]
    events = vcat(raw_events, pattern_events)
    nrow(events) > 0 && sort!(events, [:event_time, :event_index])
    coverage = artifact_rg_scope_coverage(overall.events, events, raw_events, pattern_events)
    route_summary = artifact_tool_route_summary(events)
    pattern_pressure = artifact_rg_pattern_pressure(events)
    graph = artifact_search_optimization_graph(events)
    metrics = artifact_search_optimization_metrics(graph)
    generic_opportunities = (
        nrow(overall.opportunities) == 0 || !(:search_tool in propertynames(overall.opportunities))
    ) ? overall.opportunities : overall.opportunities[overall.opportunities.search_tool .== "generic-search", :]
    opportunities = vcat(
        artifact_tool_opportunities(overall.opportunities, "rg"),
        generic_opportunities,
        artifact_rg_coverage_opportunities(coverage),
    )
    algorithm_notes = artifact_rg_algorithm_notes(events, pattern_pressure, opportunities)
    return (; events, raw_events, pattern_events, coverage, route_summary, pattern_pressure, graph, metrics, opportunities, algorithm_notes)
end

function artifact_search_strategy_table(commands::DataFrame)
    rows = DataFrame(
        event_index = Int[],
        artifact_scope = String[],
        artifact_root_relative = String[],
        relative_path = String[],
        event_phase = Int[],
        event_time = DateTime[],
        time_source = String[],
        language = String[],
        provider = String[],
        method = String[],
        operation = String[],
        command_family = String[],
        search_tool = String[],
        query_type = String[],
        query_terms = String[],
        target_hint = String[],
        route_hint = String[],
        strategy = String[],
        strategy_family = String[],
        elapsed_ms = Union{Missing,Int}[],
        exit_code = Union{Missing,Int}[],
        stdout_bytes = Union{Missing,Int}[],
        stderr_bytes = Union{Missing,Int}[],
        total_bytes = Union{Missing,Int}[],
        normalized_key = String[],
    )
    nrow(commands) == 0 && return rows

    for (event_index, row) in enumerate(eachrow(commands))
        argv = artifact_command_argv(row)
        method = artifact_row_string(row, :method)
        operation = artifact_row_string(row, :operation)
        command_family = artifact_row_string(row, :command_family)
        tool = artifact_search_tool(argv, method, operation, command_family)
        query_type = artifact_search_query_type(argv, tool, method, operation)
        query_terms = artifact_search_query_terms(argv, tool)
        target_hint = artifact_search_target_hint(argv, tool)
        route_hint = artifact_route_hint(tool, query_type, target_hint)
        strategy = artifact_search_strategy(argv, method, operation, command_family, tool, query_type, query_terms, target_hint)
        tool in SEARCH_OPTIMIZATION_TOOLS || strategy != "other" || continue

        strategy_family = artifact_search_strategy_family(strategy)
        stdout_bytes = artifact_row_int(row, :stdout_bytes)
        stderr_bytes = artifact_row_int(row, :stderr_bytes)
        total_bytes = stdout_bytes === missing || stderr_bytes === missing ? missing : stdout_bytes + stderr_bytes
        normalized_key = artifact_normalized_search_key(
            artifact_row_string(row, :language),
            isempty(strategy) ? tool : strategy,
            query_type,
            query_terms,
            target_hint,
        )

        push!(rows, (
            event_index = event_index,
            artifact_scope = artifact_row_string(row, :artifact_scope),
            artifact_root_relative = artifact_row_string(row, :artifact_root_relative),
            relative_path = artifact_row_string(row, :relative_path),
            event_phase = artifact_row_int(row, :event_phase, 0),
            event_time = artifact_row_datetime(row, :event_time),
            time_source = artifact_row_string(row, :time_source),
            language = artifact_row_string(row, :language),
            provider = artifact_row_string(row, :provider),
            method = method,
            operation = operation,
            command_family = command_family,
            search_tool = tool,
            query_type = query_type,
            query_terms = query_terms,
            target_hint = target_hint,
            route_hint = route_hint,
            strategy = strategy,
            strategy_family = strategy_family,
            elapsed_ms = artifact_row_int(row, :elapsed_ms),
            exit_code = artifact_row_int(row, :exit_code),
            stdout_bytes = stdout_bytes,
            stderr_bytes = stderr_bytes,
            total_bytes = total_bytes,
            normalized_key = normalized_key,
        ))
    end

    sort!(rows, [:event_time, :event_index])
    return rows
end

function artifact_search_strategy_summary(events::DataFrame)
    rows = DataFrame(
        artifact_scope = String[],
        strategy_family = String[],
        strategy = String[],
        events = Int[],
        distinct_normalized_keys = Int[],
        repeat_pressure = Int[],
        mean_elapsed_ms = Union{Missing,Float64}[],
        max_elapsed_ms = Union{Missing,Int}[],
        total_observed_bytes = Union{Missing,Int}[],
    )
    nrow(events) == 0 && return rows

    summary = combine(
        groupby(events, [:artifact_scope, :strategy_family, :strategy]),
        nrow => :events,
        :normalized_key => (values -> length(unique(values))) => :distinct_normalized_keys,
        :normalized_key => (values -> length(values) - length(unique(values))) => :repeat_pressure,
        :elapsed_ms => artifact_mean_skipmissing => :mean_elapsed_ms,
        :elapsed_ms => artifact_max_skipmissing => :max_elapsed_ms,
        :total_bytes => artifact_sum_skipmissing => :total_observed_bytes,
    )
    sort!(summary, [:repeat_pressure, :events, :max_elapsed_ms], rev = true)
    return summary
end

function artifact_search_strategy_transitions(events::DataFrame)
    transition_rows = DataFrame(
        artifact_scope = String[],
        from_strategy = String[],
        to_strategy = String[],
        delta_ms = Int[],
    )
    nrow(events) < 2 && return artifact_search_strategy_transition_summary(transition_rows)

    scoped = groupby(sort(events, [:artifact_scope, :event_time, :event_index]), :artifact_scope)
    for group in scoped
        nrow(group) < 2 && continue
        for index in 1:(nrow(group) - 1)
            current = group[index, :]
            next = group[index + 1, :]
            push!(transition_rows, (
                artifact_scope = current.artifact_scope,
                from_strategy = current.strategy,
                to_strategy = next.strategy,
                delta_ms = max(0, Int(Dates.value(next.event_time - current.event_time))),
            ))
        end
    end

    return artifact_search_strategy_transition_summary(transition_rows)
end

function artifact_search_strategy_transition_summary(transitions::DataFrame)
    rows = DataFrame(
        artifact_scope = String[],
        from_strategy = String[],
        to_strategy = String[],
        transitions = Int[],
        mean_delta_ms = Union{Missing,Float64}[],
        max_delta_ms = Union{Missing,Int}[],
    )
    nrow(transitions) == 0 && return rows

    summary = combine(
        groupby(transitions, [:artifact_scope, :from_strategy, :to_strategy]),
        nrow => :transitions,
        :delta_ms => artifact_mean_skipmissing => :mean_delta_ms,
        :delta_ms => artifact_max_skipmissing => :max_delta_ms,
    )
    sort!(summary, [:transitions, :max_delta_ms], rev = true)
    return summary
end

function artifact_search_strategy_graph(events::DataFrame)
    graph = SimpleDiGraph(0)
    labels = String[]
    label_to_vertex = Dict{String,Int}()

    vertex(label::AbstractString) = get!(label_to_vertex, String(label)) do
        add_vertex!(graph)
        push!(labels, String(label))
        nv(graph)
    end

    for row in eachrow(events)
        event_id = vertex("event:" * string(row.event_index))
        scope_id = vertex("scope:" * (isempty(row.artifact_scope) ? "unknown" : row.artifact_scope))
        family_id = vertex("strategy-family:" * row.strategy_family)
        strategy_id = vertex("strategy:" * row.strategy)
        tool_id = vertex("tool:" * row.search_tool)
        query_type_id = vertex("query-type:" * row.query_type)
        route_id = vertex("route-hint:" * row.route_hint)
        add_edge!(graph, event_id, scope_id)
        add_edge!(graph, scope_id, family_id)
        add_edge!(graph, family_id, strategy_id)
        add_edge!(graph, strategy_id, tool_id)
        add_edge!(graph, tool_id, query_type_id)
        add_edge!(graph, query_type_id, route_id)

        isempty(row.language) || add_edge!(graph, event_id, vertex("language:" * row.language))
        isempty(row.provider) || add_edge!(graph, event_id, vertex("provider:" * row.provider))
        isempty(row.normalized_key) || add_edge!(graph, event_id, vertex("normalized-query:" * row.normalized_key))
    end

    return ArtifactSearchOptimizationGraph(graph, labels, events)
end

function artifact_search_strategy_opportunities(events::DataFrame)
    rows = DataFrame(
        category = String[],
        target = String[],
        score = Float64[],
        evidence_count = Int[],
        evidence = String[],
        recommended_action = String[],
    )

    artifact_add_missing_graph_strategy_opportunities!(rows, events)
    nrow(events) == 0 && return rows

    artifact_add_strategy_repeat_opportunities!(rows, events)
    artifact_add_strategy_fallback_opportunities!(rows, events)
    artifact_add_scope_coverage_opportunities!(rows, events)

    sort!(rows, [:score, :evidence_count], rev=[true, true])
    return rows
end

function artifact_search_strategy_analysis(commands::DataFrame)
    events = artifact_search_strategy_table(commands)
    summary = artifact_search_strategy_summary(events)
    transitions = artifact_search_strategy_transitions(events)
    graph = artifact_search_strategy_graph(events)
    metrics = artifact_search_optimization_metrics(graph)
    opportunities = artifact_search_strategy_opportunities(events)
    return (; events, summary, transitions, graph, metrics, opportunities)
end

function artifact_search_strategy(
    argv::Vector{String},
    method::AbstractString,
    operation::AbstractString,
    command_family::AbstractString,
    tool::AbstractString,
    query_type::AbstractString,
    query_terms::AbstractString,
    target_hint::AbstractString,
)
    text = artifact_strategy_text(argv, method, operation, command_family, query_type, query_terms, target_hint)
    (occursin("graph-router", text) || occursin("graph router", text)) && return "graph-router"
    (occursin("graph-reasoning", text) || occursin("graph reasoning", text)) && return "graph-reasoning"
    (occursin("graph_turbo", text) || occursin("graph-turbo", text) ||
        occursin("semantic-graph", text) || occursin("compact graph", text)) && return "semantic-graph"
    tool == "owner-index" && return "owner-routing"
    tool == "dependency-index" && return "dependency-routing"
    tool == "prime" && return "prime-exploration"
    (tool == "rg" || query_type == "pattern-search") && return "pattern-scan"
    tool == "lexical" && return "lexical-selection"
    tool == "structural-query" && return "structural-query"
    tool == "direct-source-read" && return "direct-source-read"
    tool == "generic-search" && return "generic-search"
    occursin("router", text) && return "router-search"
    occursin("reasoning", text) && return "reasoning-search"
    return "other"
end

function artifact_strategy_text(
    argv::Vector{String},
    method::AbstractString,
    operation::AbstractString,
    command_family::AbstractString,
    query_type::AbstractString,
    query_terms::AbstractString,
    target_hint::AbstractString,
)
    return lowercase(join(vcat(argv, [method, operation, command_family, query_type, query_terms, target_hint]), " "))
end

function artifact_search_strategy_family(strategy::AbstractString)
    strategy in ("graph-router", "graph-reasoning", "semantic-graph") && return "graph-strategy"
    strategy in ("owner-routing", "dependency-routing", "prime-exploration", "router-search", "reasoning-search") && return "semantic-routing"
    strategy in ("pattern-scan", "lexical-selection", "generic-search") && return "lexical-search"
    strategy in ("structural-query", "direct-source-read") && return "structural-access"
    return "other"
end

function artifact_add_missing_graph_strategy_opportunities!(rows::DataFrame, events::DataFrame)
    for strategy in ("graph-router", "graph-reasoning", "semantic-graph")
        evidence_count = nrow(events) == 0 ? 0 : count(==(strategy), events.strategy)
        evidence_count > 0 && continue
        push!(rows, (
            category = "missing-graph-strategy-evidence",
            target = strategy,
            score = 80.0,
            evidence_count = 0,
            evidence = "no " * strategy * " events were reconstructed from provider command artifacts",
            recommended_action = "instrument search packets with explicit strategy_name, router_decision, candidate_count, and selected_edge_count",
        ))
    end
    return rows
end

function artifact_add_strategy_repeat_opportunities!(rows::DataFrame, events::DataFrame)
    grouped = combine(
        groupby(events, [:artifact_scope, :strategy, :normalized_key]),
        nrow => :events,
        :query_terms => (values -> first(values)) => :query_terms,
    )
    for row in eachrow(grouped)
        repeat_pressure = row.events - 1
        repeat_pressure <= 0 && continue
        target = join((row.artifact_scope, row.strategy, row.query_terms), " | ")
        push!(rows, (
            category = "strategy-repeat-pressure",
            target = target,
            score = Float64(row.events + repeat_pressure),
            evidence_count = row.events,
            evidence = string(repeat_pressure, " repeated events for normalized strategy key"),
            recommended_action = "cache candidate sets by normalized query and feed repeated keys into graph-router rank feedback",
        ))
    end
    return rows
end

function artifact_add_strategy_fallback_opportunities!(rows::DataFrame, events::DataFrame)
    fallback_strategies = Set(["pattern-scan", "direct-source-read", "lexical-selection"])
    graph_strategies = Set(["graph-router", "graph-reasoning", "semantic-graph"])
    sorted_events = sort(events, [:artifact_scope, :event_time, :event_index])
    for group in groupby(sorted_events, :artifact_scope)
        nrow(group) < 2 && continue
        for index in 1:(nrow(group) - 1)
            current = group[index, :]
            next = group[index + 1, :]
            current.strategy in graph_strategies || continue
            next.strategy in fallback_strategies || continue
            push!(rows, (
                category = "graph-strategy-fallback",
                target = current.artifact_scope * " | " * current.strategy * " -> " * next.strategy,
                score = 60.0,
                evidence_count = 1,
                evidence = "graph strategy was followed by lexical or source fallback in the reconstructed event stream",
                recommended_action = "record router confidence, rejected candidates, and fallback reason to separate useful fallback from routing failure",
            ))
        end
    end
    return rows
end

function artifact_add_scope_coverage_opportunities!(rows::DataFrame, events::DataFrame)
    graph_strategies = Set(["graph-router", "graph-reasoning", "semantic-graph"])
    for group in groupby(events, :artifact_scope)
        any(strategy -> strategy in graph_strategies, group.strategy) && continue
        push!(rows, (
            category = "scope-graph-coverage-gap",
            target = isempty(first(group.artifact_scope)) ? "unknown" : first(group.artifact_scope),
            score = 40.0,
            evidence_count = nrow(group),
            evidence = "scope has search activity but no reconstructed graph strategy events",
            recommended_action = "emit graph strategy metadata for this scope or mark the provider as graph-strategy-disabled",
        ))
    end
    return rows
end

function artifact_add_repeat_search_opportunities!(rows::DataFrame, events::DataFrame)
    grouped = combine(groupby(events, :normalized_key), nrow => :count, :elapsed_ms => artifact_sum_int => :elapsed_total_ms)
    for row in eachrow(grouped)
        row.count > 1 || continue
        push!(rows, (
            category = "repeat-search",
            target = row.normalized_key,
            score = Float64(row.count * 100 + row.elapsed_total_ms),
            evidence_count = row.count,
            evidence = row.normalized_key,
            recommended_action = "Cache or promote this repeated search shape to a typed route before invoking lexical/rg again.",
        ))
    end
end

function artifact_add_latency_opportunities!(rows::DataFrame, events::DataFrame)
    grouped = combine(
        groupby(events, [:search_tool, :query_type]),
        nrow => :count,
        :elapsed_ms => artifact_p90_ms => :elapsed_p90_ms,
        :elapsed_ms => artifact_max_ms => :elapsed_max_ms,
    )
    for row in eachrow(grouped)
        p90 = row.elapsed_p90_ms === missing ? 0 : row.elapsed_p90_ms
        max_ms = row.elapsed_max_ms === missing ? 0 : row.elapsed_max_ms
        max(p90, max_ms) > 0 || continue
        push!(rows, (
            category = "latency-hotspot",
            target = row.search_tool * "/" * row.query_type,
            score = Float64(max(p90, max_ms) + row.count * 10),
            evidence_count = row.count,
            evidence = "p90=" * string(p90) * " max=" * string(max_ms),
            recommended_action = "Benchmark this tool/query type and compare against a typed index or cached structural selector route.",
        ))
    end
end

function artifact_add_tool_route_opportunities!(rows::DataFrame, events::DataFrame)
    for tool in ("lexical", "rg")
        subset = events[events.search_tool .== tool, :]
        nrow(subset) == 0 && continue
        action = tool == "lexical" ?
            "Promote repeated lexical owner discovery to owner/dependency topology packets." :
            "Convert repeated rg patterns into indexed symbol, call, or docs-use queries."
        push!(rows, (
            category = tool * "-route-optimization",
            target = tool,
            score = Float64(nrow(subset) * 75 + artifact_sum_int(subset.elapsed_ms)),
            evidence_count = nrow(subset),
            evidence = join(unique(subset.query_type), ","),
            recommended_action = action,
        ))
    end

    unknown = events[in.(events.search_tool, Ref(["generic-search", "generic-query"])), :]
    nrow(unknown) == 0 && return
    push!(rows, (
        category = "route-classification-gap",
        target = "generic-search-query",
        score = Float64(nrow(unknown) * 50),
        evidence_count = nrow(unknown),
        evidence = join(unique(unknown.operation), ","),
        recommended_action = "Add method or argv fields that distinguish this generic search/query route before optimizing it.",
    ))
end

function artifact_add_time_source_opportunities!(rows::DataFrame, events::DataFrame)
    fallback = events[events.time_source .== "mtime", :]
    nrow(fallback) == 0 && return
    push!(rows, (
        category = "time-instrumentation-gap",
        target = "mtime-fallback",
        score = Float64(nrow(fallback) * 25),
        evidence_count = nrow(fallback),
        evidence = join(unique(fallback.relative_path), "; "),
        recommended_action = "Add eventTimestampMs/startedAtMs to these artifact writers before making phase-order claims.",
    ))
end

function artifact_command_argv(row)
    argv_json = artifact_row_string(row, :argv_json)
    if !isempty(argv_json)
        parsed = try
            JSON.parse(argv_json)
        catch
            nothing
        end
        parsed isa AbstractVector && return [artifact_string(value) for value in parsed]
    end
    argv_text = artifact_row_string(row, :argv_text)
    return isempty(argv_text) ? String[] : split(argv_text)
end

function artifact_search_tool(argv::Vector{String}, method::AbstractString, operation::AbstractString, command_family::AbstractString)
    lower_argv = lowercase.(argv)
    lower_method = lowercase(method)
    lower_operation = lowercase(operation)
    lower_family = lowercase(command_family)

    any(token -> basename(token) == "rg" || endswith(token, "/rg"), lower_argv) && return "rg"
    any(token -> token == "lexical", lower_argv) && return "lexical"
    any(token -> token == "direct-source-read", lower_argv) && return "direct-source-read"
    (occursin("search/lexical", lower_method) || occursin("search lexical", lower_operation)) && return "lexical"
    occursin("rg", lower_family) && return "rg"
    (occursin("search/prime", lower_method) || occursin("search prime", lower_operation)) && return "prime"
    (occursin("search/owner", lower_method) || occursin("search owner", lower_operation)) && return "owner-index"
    if occursin("search/deps", lower_method) || occursin("search/dependency", lower_method) ||
            occursin("search deps", lower_operation) || occursin("search dependency", lower_operation)
        return "dependency-index"
    end
    (occursin("direct-source-read", lower_method) || occursin("direct-source-read", lower_operation)) && return "direct-source-read"
    (startswith(lower_method, "query") || startswith(lower_operation, "query")) && return "structural-query"
    (startswith(lower_method, "search") || startswith(lower_operation, "search")) && return "generic-search"
    return "other"
end

function artifact_search_query_type(argv::Vector{String}, tool::AbstractString, method::AbstractString, operation::AbstractString)
    if tool == "lexical"
        mode = artifact_token_after(argv, "lexical", 2)
        return isempty(mode) ? "lexical" : "lexical-" * mode
    elseif tool == "rg"
        return any(token -> startswith(token, "--json"), argv) ? "rg-json-pattern" : "rg-pattern"
    elseif tool == "prime"
        return "prime"
    elseif tool == "owner-index"
        return "owner"
    elseif tool == "dependency-index"
        return "dependency"
    elseif operation == "search pattern"
        return "pattern-search"
    elseif tool == "direct-source-read"
        return "direct-source-read"
    elseif tool == "structural-query"
        lowered = lowercase(method * " " * operation)
        occursin("owner-items", lowered) && return "owner-items"
        occursin("code", lowered) && return "code"
        return "selector"
    end
    return tool
end

function artifact_search_query_terms(argv::Vector{String}, tool::AbstractString)
    if tool == "lexical"
        return artifact_token_after(argv, "lexical", 1)
    elseif tool == "rg"
        index = findfirst(token -> basename(lowercase(token)) == "rg", argv)
        index === nothing && return ""
        for token in argv[(index + 1):end]
            startswith(token, "-") && continue
            return token
        end
    elseif tool == "owner-index"
        return artifact_token_after(argv, "owner", 1)
    elseif tool == "dependency-index"
        terms = artifact_token_after(argv, "deps", 1)
        isempty(terms) || return terms
        return artifact_token_after(argv, "dependency", 1)
    end
    terms = artifact_token_after(argv, "pattern", 1)
    isempty(terms) || return terms
    selector = artifact_option_value(argv, "--selector")
    isempty(selector) || return selector
    return ""
end

function artifact_search_target_hint(argv::Vector{String}, tool::AbstractString)
    selector = artifact_option_value(argv, "--selector")
    isempty(selector) || return selector
    tool == "rg" && length(argv) >= 3 && return last(argv)
    tool == "owner-index" && return artifact_token_after(argv, "owner", 1)
    tool == "dependency-index" && return artifact_token_after(argv, "deps", 1)
    return ""
end

function artifact_route_hint(tool::AbstractString, query_type::AbstractString, target_hint::AbstractString)
    tool == "lexical" && return "promote-lexical-to-owner-index"
    tool == "rg" && return "promote-rg-to-structural-index"
    tool == "prime" && return "reuse-prime-topology"
    tool == "owner-index" && return "owner-route"
    tool == "dependency-index" && return "dependency-route"
    tool == "direct-source-read" && return isempty(target_hint) ? "selector-gap" : "direct-selector"
    tool == "structural-query" && return query_type
    return "classify-route"
end

function artifact_normalized_search_key(
    language::AbstractString,
    tool::AbstractString,
    query_type::AbstractString,
    query_terms::AbstractString,
    target_hint::AbstractString,
)
    return join((language, tool, query_type, lowercase(strip(query_terms)), strip(target_hint)), "|")
end

function artifact_option_value(argv::Vector{String}, option::AbstractString)
    for index in eachindex(argv)
        token = argv[index]
        token == option && index < length(argv) && return argv[index + 1]
        startswith(token, option * "=") && return last(split(token, "=", limit=2))
    end
    return ""
end

function artifact_token_after(argv::Vector{String}, token::AbstractString, offset::Integer)
    index = findfirst(value -> lowercase(value) == lowercase(token), argv)
    index === nothing && return ""
    target_index = index + Int(offset)
    return target_index <= length(argv) ? argv[target_index] : ""
end

function artifact_row_string(row, name::Symbol, default::String="")
    String(name) in names(parent(row)) || return default
    value = row[name]
    value === missing && return default
    return artifact_string(value)
end

function artifact_row_int(row, name::Symbol, default=missing)
    String(name) in names(parent(row)) || return default
    value = row[name]
    value === missing && return default
    value isa Integer && return Int(value)
    value isa AbstractString && return something(tryparse(Int, value), default)
    return default
end

function artifact_row_datetime(row, name::Symbol)
    String(name) in names(parent(row)) || return DateTime(0)
    value = row[name]
    value isa DateTime && return value
    return DateTime(0)
end

function artifact_sum_int(values)
    total = 0
    for value in skipmissing(values)
        value isa Integer || continue
        total += Int(value)
    end
    return total
end
