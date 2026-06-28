struct ArtifactActionFlowGraph
    graph::SimpleDiGraph
    labels::Vector{String}
    commands::DataFrame
    packets::DataFrame
end

const ARTIFACT_PACKET_DIRS = Set([
    "search",
    "query",
    "analysis-metadata",
    "semantic-tree-sitter-query",
])

const ARTIFACT_TIME_KEYS = (
    "eventTimestampMs",
    "startedAtMs",
    "endedAtMs",
    "timestampMs",
    "timestamp_ms",
    "timestamp",
)

function artifact_json_inventory(root::AbstractString)
    rows = DataFrame(
        relative_path = String[],
        top_dir = String[],
        schema_id = String[],
        method = String[],
        language = String[],
        provider = String[],
        source_artifact_id = String[],
        prompt_output_artifact_id = String[],
        byte_size = Int[],
        weak_mtime = DateTime[],
        event_time = DateTime[],
        time_source = String[],
        parse_status = String[],
        error_message = String[],
    )

    for path in artifact_json_files(root)
        relative = relpath(path, root)
        top = artifact_top_dir(relative)
        parsed, error = parse_artifact_json(path)
        if error !== nothing || !(parsed isa AbstractDict)
            push!(rows, (
                relative_path = relative,
                top_dir = top,
                schema_id = "",
                method = "",
                language = "",
                provider = "",
                source_artifact_id = "",
                prompt_output_artifact_id = "",
                byte_size = filesize(path),
                weak_mtime = artifact_mtime(path),
                event_time = artifact_mtime(path),
                time_source = "mtime",
                parse_status = "error",
                error_message = artifact_string(error),
            ))
            continue
        end

        event_time, time_source = artifact_event_time(parsed, path)

        push!(rows, (
            relative_path = relative,
            top_dir = top,
            schema_id = artifact_get_string(parsed, "schemaId"),
            method = artifact_get_string(parsed, "method"),
            language = artifact_get_string(parsed, "languageId"),
            provider = artifact_get_string(parsed, "providerId"),
            source_artifact_id = artifact_get_string(parsed, "sourceArtifactId"),
            prompt_output_artifact_id = artifact_get_string(parsed, "promptOutputArtifactId"),
            byte_size = filesize(path),
            weak_mtime = artifact_mtime(path),
            event_time = event_time,
            time_source = time_source,
            parse_status = "ok",
            error_message = "",
        ))
    end

    return rows
end

function artifact_search_packet_table(root::AbstractString)
    rows = DataFrame(
        relative_path = String[],
        top_dir = String[],
        schema_id = String[],
        method = String[],
        language = String[],
        provider = String[],
        query = String[],
        view = String[],
        source_artifact_id = String[],
        prompt_output_artifact_id = String[],
        weak_mtime = DateTime[],
        event_time = DateTime[],
        time_source = String[],
    )

    for path in artifact_json_files(root)
        relative = relpath(path, root)
        top = artifact_top_dir(relative)
        top in ARTIFACT_PACKET_DIRS || continue
        parsed, error = parse_artifact_json(path)
        error === nothing && parsed isa AbstractDict || continue
        event_time, time_source = artifact_event_time(parsed, path)

        push!(rows, (
            relative_path = relative,
            top_dir = top,
            schema_id = artifact_get_string(parsed, "schemaId"),
            method = artifact_get_string(parsed, "method"),
            language = artifact_get_string(parsed, "languageId"),
            provider = artifact_get_string(parsed, "providerId"),
            query = artifact_get_string(parsed, "query"),
            view = artifact_get_string(parsed, "view"),
            source_artifact_id = artifact_get_string(parsed, "sourceArtifactId"),
            prompt_output_artifact_id = artifact_get_string(parsed, "promptOutputArtifactId"),
            weak_mtime = artifact_mtime(path),
            event_time = event_time,
            time_source = time_source,
        ))
    end

    return rows
end

function artifact_provider_command_table(root::AbstractString; phase_buckets::Integer=4)
    rows = DataFrame(
        relative_path = String[],
        top_dir = String[],
        method = String[],
        language = String[],
        provider = String[],
        executable = String[],
        operation = String[],
        command_family = String[],
        argv_text = String[],
        argv_json = String[],
        elapsed_ms = Union{Missing,Int}[],
        exit_code = Union{Missing,Int}[],
        stdout_bytes = Union{Missing,Int}[],
        stderr_bytes = Union{Missing,Int}[],
        weak_mtime = DateTime[],
        event_time = DateTime[],
        time_source = String[],
    )

    for path in artifact_json_files(root)
        parsed, error = parse_artifact_json(path)
        error === nothing && parsed isa AbstractDict || continue
        commands = get(parsed, "providerCommands", nothing)
        commands isa AbstractVector || continue

        relative = relpath(path, root)
        top = artifact_top_dir(relative)
        method = artifact_get_string(parsed, "method")
        isempty(method) && (method = top)

        for command in commands
            command isa AbstractDict || continue
            argv = get(command, "argv", Any[])
            argv isa AbstractVector || continue
            argv_strings = [artifact_string(arg) for arg in argv]
            executable = isempty(argv_strings) ? "" : basename(argv_strings[1])
            event_time, time_source = artifact_command_event_time(command, parsed, path)
            push!(rows, (
                relative_path = relative,
                top_dir = top,
                method = method,
                language = artifact_get_string(command, "languageId"),
                provider = artifact_get_string(command, "providerId"),
                executable = executable,
                operation = artifact_command_operation(argv_strings),
                command_family = artifact_command_family(argv_strings),
                argv_text = join(argv_strings, " "),
                argv_json = JSON.json(argv_strings),
                elapsed_ms = artifact_get_int(command, "elapsedMs"),
                exit_code = artifact_get_int(command, "exitCode"),
                stdout_bytes = artifact_get_int(command, "stdoutBytes"),
                stderr_bytes = artifact_get_int(command, "stderrBytes"),
                weak_mtime = artifact_mtime(path),
                event_time = event_time,
                time_source = time_source,
            ))
        end
    end

    rows[!, :event_phase] = weak_phase_ids(rows.event_time; buckets=phase_buckets)
    rows[!, :weak_phase] = copy(rows.event_phase)
    return rows
end

function artifact_action_taxonomy(commands::DataFrame)
    output = DataFrame(
        language = String[],
        provider = String[],
        operation = String[],
        command_family = String[],
        count = Int[],
        elapsed_p50_ms = Union{Missing,Int}[],
        elapsed_p90_ms = Union{Missing,Int}[],
        elapsed_max_ms = Union{Missing,Int}[],
    )
    nrow(commands) == 0 && return output

    grouped = groupby(commands, [:language, :provider, :operation, :command_family])
    output = combine(
        grouped,
        nrow => :count,
        :elapsed_ms => artifact_median_ms => :elapsed_p50_ms,
        :elapsed_ms => artifact_p90_ms => :elapsed_p90_ms,
        :elapsed_ms => artifact_max_ms => :elapsed_max_ms,
    )
    sort!(output, [:count, :elapsed_p90_ms], rev=[true, true])
    return output
end

function artifact_phase_table(commands::DataFrame)
    output = DataFrame(
        event_phase = Int[],
        phase_start = DateTime[],
        phase_end = DateTime[],
        command_count = Int[],
        json_timed_count = Int[],
        mtime_fallback_count = Int[],
        dominant_language = String[],
        dominant_operation = String[],
    )
    nrow(commands) == 0 && return output

    for group in groupby(commands, :event_phase)
        push!(output, (
            event_phase = first(group.event_phase),
            phase_start = minimum(group.event_time),
            phase_end = maximum(group.event_time),
            command_count = nrow(group),
            json_timed_count = count(!=("mtime"), group.time_source),
            mtime_fallback_count = count(==("mtime"), group.time_source),
            dominant_language = dominant_value(group.language),
            dominant_operation = dominant_value(group.operation),
        ))
    end
    sort!(output, :event_phase)
    return output
end

function dominant_value(values)
    counts = artifact_count_by(identity, values)
    isempty(counts) && return ""
    pair = first(sort(collect(counts), by=last, rev=true))
    return string(first(pair))
end

function artifact_count_by(transform, values)
    counts = Dict{String,Int}()
    for value in values
        key = string(transform(value))
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

function artifact_time_gap_table(
    inventory::DataFrame,
    packets::DataFrame=DataFrame(),
    commands::DataFrame=DataFrame(),
)
    rows = DataFrame(
        artifact_scope = String[],
        source_table = String[],
        top_dir = String[],
        time_source = String[],
        count = Int[],
    )

    for (source_table, table) in (
        ("inventory", inventory),
        ("packets", packets),
        ("commands", commands),
    )
        nrow(table) == 0 && continue
        all(name -> name in names(table), ["top_dir", "time_source"]) || continue
        group_columns = "artifact_scope" in names(table) ? [:artifact_scope, :top_dir, :time_source] : [:top_dir, :time_source]
        grouped = combine(groupby(table, group_columns), nrow => :count)
        for row in eachrow(grouped)
            push!(rows, (
                artifact_scope = "artifact_scope" in names(parent(row)) ? row.artifact_scope : "",
                source_table = source_table,
                top_dir = row.top_dir,
                time_source = row.time_source,
                count = row.count,
            ))
        end
    end

    sort!(rows, [:artifact_scope, :source_table, :top_dir, :time_source])
    return rows
end

function artifact_action_flow_graph(commands::DataFrame, packets::DataFrame=DataFrame())
    graph = SimpleDiGraph(0)
    labels = String[]
    label_to_vertex = Dict{String,Int}()

    vertex(label::AbstractString) = get!(label_to_vertex, String(label)) do
        add_vertex!(graph)
        push!(labels, String(label))
        nv(graph)
    end

    for row in eachrow(commands)
        artifact_id = vertex("artifact:" * artifact_scoped_relative(row))
        scope = artifact_flow_row_string(row, :artifact_scope)
        phase_id = vertex("phase:" * string(row.event_phase))
        language_id = vertex("language:" * row.language)
        provider_id = vertex("provider:" * row.provider)
        method_id = vertex("method:" * row.method)
        operation_id = vertex("operation:" * row.operation)
        family_id = vertex("family:" * row.command_family)
        if isempty(scope)
            add_edge!(graph, artifact_id, phase_id)
        else
            scope_id = vertex("scope:" * scope)
            add_edge!(graph, artifact_id, scope_id)
            add_edge!(graph, scope_id, phase_id)
        end
        add_edge!(graph, phase_id, language_id)
        add_edge!(graph, language_id, provider_id)
        add_edge!(graph, provider_id, method_id)
        add_edge!(graph, method_id, operation_id)
        add_edge!(graph, operation_id, family_id)
    end

    for row in eachrow(packets)
        packet_id = vertex("packet:" * artifact_scoped_relative(row))
        scope = artifact_flow_row_string(row, :artifact_scope)
        method_id = vertex("method:" * row.method)
        language_id = vertex("language:" * row.language)
        provider_id = vertex("provider:" * row.provider)
        if isempty(scope)
            add_edge!(graph, packet_id, method_id)
        else
            scope_id = vertex("scope:" * scope)
            add_edge!(graph, packet_id, scope_id)
            add_edge!(graph, scope_id, method_id)
        end
        add_edge!(graph, method_id, language_id)
        add_edge!(graph, language_id, provider_id)
    end

    return ArtifactActionFlowGraph(graph, labels, commands, packets)
end

function artifact_action_flow_metrics(flow::ArtifactActionFlowGraph)
    graph = flow.graph
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
    for label in flow.labels
        kind, name = artifact_label_parts(label)
        push!(kinds, kind)
        push!(names, name)
    end

    metrics = DataFrame(
        vertex = collect(1:vertex_count),
        label = flow.labels,
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

function artifact_research_dataset(root::AbstractString; phase_buckets::Integer=4)
    repo_root = artifact_default_repo_root(root)
    return artifact_research_dataset_from_roots([root]; repo_root, phase_buckets)
end

function artifact_research_dataset_from_repo(repo_root::AbstractString; phase_buckets::Integer=4)
    roots = artifact_discover_roots(repo_root)
    return artifact_research_dataset_from_roots(roots; repo_root, phase_buckets)
end

function artifact_research_dataset_from_roots(
    roots::AbstractVector{<:AbstractString};
    repo_root::AbstractString=isempty(roots) ? pwd() : artifact_default_repo_root(first(roots)),
    phase_buckets::Integer=4,
)
    artifact_roots = artifact_root_table(repo_root, roots)

    inventory_tables = DataFrame[]
    packet_tables = DataFrame[]
    command_tables = DataFrame[]

    for artifact_root in artifact_roots.artifact_root
        push!(inventory_tables, artifact_annotate_root!(artifact_json_inventory(artifact_root), repo_root, artifact_root))
        push!(packet_tables, artifact_annotate_root!(artifact_search_packet_table(artifact_root), repo_root, artifact_root))
        push!(command_tables, artifact_annotate_root!(artifact_provider_command_table(artifact_root; phase_buckets), repo_root, artifact_root))
    end

    inventory = artifact_vcat_tables(inventory_tables)
    packets = artifact_vcat_tables(packet_tables)
    commands = artifact_vcat_tables(command_tables)
    taxonomy = artifact_action_taxonomy(commands)
    phases = artifact_phase_table(commands)
    time_gaps = artifact_time_gap_table(inventory, packets, commands)
    flow = artifact_action_flow_graph(commands, packets)
    flow_metrics = artifact_action_flow_metrics(flow)
    return (;
        artifact_roots,
        inventory,
        packets,
        commands,
        taxonomy,
        phases,
        time_gaps,
        flow,
        flow_metrics,
    )
end

function artifact_json_files(root::AbstractString)
    isdir(root) || return String[]
    files = String[]
    for (dir, _, names) in walkdir(root)
        for name in names
            endswith(name, ".json") || continue
            push!(files, joinpath(dir, name))
        end
    end
    sort!(files)
    return files
end

const ASP_ARTIFACT_RELATIVE_ROOT = joinpath(".cache", "agent-semantic-protocol", "artifacts")

function artifact_discover_roots(repo_root::AbstractString)
    roots = String[]
    workspace_root = joinpath(repo_root, ASP_ARTIFACT_RELATIVE_ROOT)
    isdir(workspace_root) && push!(roots, workspace_root)

    languages_root = joinpath(repo_root, "languages")
    if isdir(languages_root)
        for language_name in sort(readdir(languages_root))
            artifact_root = joinpath(languages_root, language_name, ASP_ARTIFACT_RELATIVE_ROOT)
            isdir(artifact_root) && push!(roots, artifact_root)
        end
    end

    return unique(normpath.(roots))
end

function artifact_root_scope(repo_root::AbstractString, artifact_root::AbstractString)
    relative = relpath(artifact_root, repo_root)
    relative == ASP_ARTIFACT_RELATIVE_ROOT && return "workspace"
    parts = splitpath(relative)
    length(parts) >= 2 && parts[1] == "languages" && return "language:" * parts[2]
    return relative
end

function artifact_root_table(repo_root::AbstractString, roots::AbstractVector{<:AbstractString})
    normalized_roots = unique(normpath.(String.(roots)))
    existing_roots = [root for root in normalized_roots if isdir(root)]
    return DataFrame(
        artifact_root = existing_roots,
        artifact_scope = [artifact_root_scope(repo_root, root) for root in existing_roots],
        artifact_root_relative = [relpath(root, repo_root) for root in existing_roots],
        json_file_count = [length(artifact_json_files(root)) for root in existing_roots],
    )
end

function artifact_annotate_root!(table::DataFrame, repo_root::AbstractString, artifact_root::AbstractString)
    table[!, :artifact_root] = fill(normpath(artifact_root), nrow(table))
    table[!, :artifact_scope] = fill(artifact_root_scope(repo_root, artifact_root), nrow(table))
    table[!, :artifact_root_relative] = fill(relpath(artifact_root, repo_root), nrow(table))
    return table
end

function artifact_vcat_tables(tables::Vector{DataFrame})
    isempty(tables) && return DataFrame()
    return vcat(tables...; cols=:union)
end

function artifact_default_repo_root(artifact_root::AbstractString)
    normalized = normpath(artifact_root)
    parts = splitpath(normalized)
    suffix = splitpath(ASP_ARTIFACT_RELATIVE_ROOT)
    if length(parts) >= length(suffix) && parts[(end - length(suffix) + 1):end] == suffix
        prefix = parts[1:(end - length(suffix))]
        isempty(prefix) && return pwd()
        return normpath(joinpath(prefix...))
    end
    return dirname(normalized)
end

function artifact_flow_row_string(row, name::Symbol, default::String="")
    String(name) in names(parent(row)) || return default
    value = row[name]
    value === missing && return default
    return artifact_string(value)
end

function artifact_scoped_relative(row)
    relative = artifact_flow_row_string(row, :relative_path)
    scope = artifact_flow_row_string(row, :artifact_scope)
    isempty(scope) && return relative
    return scope * ":" * relative
end

function parse_artifact_json(path::AbstractString)
    try
        return JSON.parsefile(path), nothing
    catch error
        return nothing, error
    end
end

artifact_top_dir(relative::AbstractString) = first(splitpath(relative))
artifact_mtime(path::AbstractString) = unix2datetime(stat(path).mtime)

function artifact_event_time(mapping::AbstractDict, path::AbstractString)
    explicit = artifact_json_time(mapping)
    explicit === missing || return explicit, "artifact-json"
    return artifact_mtime(path), "mtime"
end

function artifact_command_event_time(
    command::AbstractDict,
    packet::AbstractDict,
    path::AbstractString,
)
    explicit = artifact_json_time(command)
    explicit === missing || return explicit, "command-json"
    explicit = artifact_json_time(packet)
    explicit === missing || return explicit, "packet-json"
    return artifact_mtime(path), "mtime"
end

function artifact_json_time(mapping::AbstractDict)
    for key in ARTIFACT_TIME_KEYS
        value = artifact_get_int(mapping, key)
        value === missing && continue
        value < 0 && continue
        return unix2datetime(value / 1000)
    end
    return missing
end

function artifact_get_string(mapping::AbstractDict, key::AbstractString)
    value = get(mapping, key, "")
    return artifact_string(value)
end

function artifact_get_int(mapping::AbstractDict, key::AbstractString)
    value = get(mapping, key, missing)
    value isa Missing && return missing
    value isa Integer && return Int(value)
    value isa AbstractString && return something(tryparse(Int, value), missing)
    return missing
end

function artifact_string(value)
    value === nothing && return ""
    value isa AbstractString && return String(value)
    return string(value)
end

function artifact_command_operation(argv::Vector{String})
    length(argv) >= 3 && return argv[2] * " " * argv[3]
    length(argv) >= 2 && return argv[2]
    return ""
end

function artifact_command_family(argv::Vector{String})
    isempty(argv) && return ""
    executable = basename(argv[1])
    length(argv) >= 2 || return executable
    return executable * " " * argv[2]
end

function weak_phase_ids(times::AbstractVector{DateTime}; buckets::Integer=4)
    n = length(times)
    n == 0 && return Int[]
    bucket_count = max(Int(buckets), 1)
    phase = zeros(Int, n)
    for (rank, index) in enumerate(sortperm(times))
        phase[index] = min(bucket_count, floor(Int, (rank - 1) * bucket_count / n) + 1)
    end
    return phase
end

function artifact_values(values)
    return collect(skipmissing(values))
end

function artifact_median_ms(values)
    clean = artifact_values(values)
    isempty(clean) && return missing
    return round(Int, median(clean))
end

function artifact_p90_ms(values)
    clean = sort(artifact_values(values))
    isempty(clean) && return missing
    index = max(1, ceil(Int, 0.9 * length(clean)))
    return Int(clean[index])
end

function artifact_max_ms(values)
    clean = artifact_values(values)
    isempty(clean) && return missing
    return maximum(clean)
end

function artifact_label_parts(label::AbstractString)
    parts = split(label, ":", limit=2)
    length(parts) == 2 || return ("unknown", String(label))
    return (String(parts[1]), String(parts[2]))
end
