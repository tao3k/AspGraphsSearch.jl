using AspGraphsSearch
using Dates
using Graphs
using JSON
using Test

@testset "ASP artifact search graph" begin
    mktempdir() do dir
        artifact = joinpath(dir, "session.org")
        write(
            artifact,
            """
            * Evidence
            Run `asp rust search deps serde --workspace . --view seeds`.
            Then run `asp search --language python query graph_turbo --workspace .`.
            A generic fallback was `asp search graph docs --workspace .`.
            Ignore `cargo test`.
            """,
        )

        records = collect_search_commands(dir)
        @test length(records) == 3
        @test records[1].language == "rust"
        @test records[1].verb == "search"
        @test records[2].language == "python"
        @test records[2].verb == "search"
        @test records[3].language === nothing

        artifact_graph = search_command_graph(records)
        summary = summarize_search_graph(artifact_graph)
        @test summary.record_count == 3
        @test summary.languages["rust"] == 1
        @test summary.languages["python"] == 1
        @test summary.languages["<generic>"] == 1
        @test summary.verbs["search"] == 3

        commands = artifact_command_table(records)
        @test names(commands) == ["source_path", "command", "language", "verb", "operation", "arg_count", "signature"]
        @test commands.operation == ["deps", "query", "graph"]

        metrics = artifact_graph_metrics(artifact_graph)
        @test size(metrics, 1) == summary.vertex_count
        @test "operation:deps" in metrics.label

        ranked = personalized_artifact_rank(artifact_graph; seed_prefixes=("operation:deps",))
        @test size(ranked, 1) == size(metrics, 1)
        @test ranked.ppr_score[1] >= ranked.ppr_score[end]

        opportunities = artifact_improvement_opportunities(artifact_graph)
        @test size(opportunities, 1) >= 1
        @test "missing-language-facade" in opportunities.category

        analysis = artifact_algorithm_analysis(records; root=dir)
        @test analysis.summary.record_count == 3
        @test size(analysis.commands, 1) == 3

        spec = research_experiment_spec(records; root=dir)
        @test !isnothing(spec)

        mkpath(joinpath(dir, "prompt-output"))
        mkpath(joinpath(dir, "search"))
        mkpath(joinpath(dir, "query"))

        write(
            joinpath(dir, "prompt-output", "rust-search-owner-abc.command.json"),
            JSON.json(Dict(
                "schemaId" => "agent.semantic-protocols.client-prompt-output-command",
                "schemaVersion" => "1",
                "protocolId" => "agent.semantic-protocols.client",
                "protocolVersion" => "1",
                "promptOutputArtifactId" => "prompt-output/rust-search-owner-abc.txt",
                "eventTimestampMs" => 1_700_000_000_000,
                "providerCommands" => [
                    Dict(
                        "argv" => ["/tmp/rs-harness", "search", "owner", "src/lib.rs", "items", "--view", "seeds"],
                        "startedAtMs" => 1_700_000_000_100,
                        "elapsedMs" => 42,
                        "exitCode" => 0,
                        "languageId" => "rust",
                        "providerId" => "rs-harness",
                        "stdoutBytes" => 100,
                        "stderrBytes" => 0,
                    ),
                ],
            )),
        )
        write(
            joinpath(dir, "search", "rust-search-owner-abc.json"),
            JSON.json(Dict(
                "schemaId" => "agent.semantic-protocols.semantic-search-packet",
                "schemaVersion" => "1",
                "protocolId" => "agent.semantic-protocols",
                "protocolVersion" => "1",
                "languageId" => "rust",
                "providerId" => "rs-harness",
                "method" => "search/owner",
                "query" => "src/lib.rs",
                "view" => "owner",
                "eventTimestampMs" => 1_700_000_000_200,
            )),
        )
        write(
            joinpath(dir, "query", "rust-query-owner-items-def.json"),
            JSON.json(Dict(
                "schemaId" => "agent.semantic-protocols.semantic-query-packet",
                "schemaVersion" => "1",
                "protocolId" => "agent.semantic-protocols",
                "protocolVersion" => "1",
                "languageId" => "rust",
                "providerId" => "rs-harness",
                "method" => "query/owner-items",
                "query" => "owner",
            )),
        )

        inventory = artifact_json_inventory(dir)
        @test size(inventory, 1) == 3
        @test all(inventory.parse_status .== "ok")
        @test "event_time" in names(inventory)
        @test "time_source" in names(inventory)
        @test count(==("artifact-json"), inventory.time_source) == 2

        packets = artifact_search_packet_table(dir)
        @test size(packets, 1) == 2
        @test Set(packets.method) == Set(["search/owner", "query/owner-items"])
        @test Set(packets.time_source) == Set(["artifact-json", "mtime"])

        provider_commands = artifact_provider_command_table(dir)
        @test size(provider_commands, 1) == 1
        @test provider_commands.operation == ["search owner"]
        @test provider_commands.command_family == ["rs-harness search"]
        @test provider_commands.argv_json == [JSON.json(["/tmp/rs-harness", "search", "owner", "src/lib.rs", "items", "--view", "seeds"])]
        @test provider_commands.time_source == ["command-json"]
        @test provider_commands.event_time[1] > DateTime(2023)

        taxonomy = artifact_action_taxonomy(provider_commands)
        @test size(taxonomy, 1) == 1
        @test taxonomy.count == [1]
        @test taxonomy.elapsed_p50_ms == [42]

        phases = artifact_phase_table(provider_commands)
        @test size(phases, 1) == 1
        @test phases.json_timed_count == [1]
        @test phases.mtime_fallback_count == [0]
        @test phases.dominant_language == ["rust"]
        @test phases.dominant_operation == ["search owner"]

        time_gaps = artifact_time_gap_table(inventory, packets, provider_commands)
        @test size(time_gaps, 1) >= 3
        @test "mtime" in time_gaps.time_source

        flow = artifact_action_flow_graph(provider_commands, packets)
        @test nv(flow.graph) > 0
        flow_metrics = artifact_action_flow_metrics(flow)
        @test size(flow_metrics, 1) == nv(flow.graph)
        @test "operation:search owner" in flow_metrics.label

        dataset = artifact_research_dataset(dir)
        @test size(dataset.inventory, 1) == 3
        @test size(dataset.commands, 1) == 1
        @test size(dataset.packets, 1) == 2
        @test size(dataset.time_gaps, 1) >= 3
    end
end

@testset "search optimization analyzer" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "prompt-output"))
        write(
            joinpath(dir, "prompt-output", "rust-search-optimization.command.json"),
            JSON.json(Dict(
                "schemaId" => "agent.semantic-protocols.client-prompt-output-command",
                "schemaVersion" => "1",
                "protocolId" => "agent.semantic-protocols.client",
                "protocolVersion" => "1",
                "eventTimestampMs" => 1_700_001_000_000,
                "providerCommands" => [
                    Dict(
                        "argv" => ["rs-harness", "search", "lexical", "GraphTurbo", "owner", "--view", "seeds"],
                        "startedAtMs" => 1_700_001_000_010,
                        "elapsedMs" => 120,
                        "exitCode" => 0,
                        "languageId" => "rust",
                        "providerId" => "rs-harness",
                        "stdoutBytes" => 80,
                        "stderrBytes" => 0,
                    ),
                    Dict(
                        "argv" => ["rs-harness", "search", "lexical", "GraphTurbo", "owner", "--view", "seeds"],
                        "startedAtMs" => 1_700_001_000_020,
                        "elapsedMs" => 180,
                        "exitCode" => 0,
                        "languageId" => "rust",
                        "providerId" => "rs-harness",
                        "stdoutBytes" => 82,
                        "stderrBytes" => 0,
                    ),
                    Dict(
                        "argv" => ["rg", "GraphTurbo", "src", "--json"],
                        "startedAtMs" => 1_700_001_000_030,
                        "elapsedMs" => 220,
                        "exitCode" => 0,
                        "languageId" => "rust",
                        "providerId" => "rg",
                        "stdoutBytes" => 30,
                        "stderrBytes" => 0,
                    ),
                    Dict(
                        "argv" => ["rs-harness", "query", "--from-hook", "direct-source-read", "--selector", "src/lib.rs:1-10", "--code"],
                        "startedAtMs" => 1_700_001_000_040,
                        "elapsedMs" => 40,
                        "exitCode" => 0,
                        "languageId" => "rust",
                        "providerId" => "rs-harness",
                        "stdoutBytes" => 200,
                        "stderrBytes" => 0,
                    ),
                ],
            )),
        )

        commands = artifact_provider_command_table(dir)
        events = artifact_search_tool_table(commands)
        @test size(events, 1) == 4
        @test count(==("lexical"), events.search_tool) == 2
        @test "rg" in events.search_tool
        @test "direct-source-read" in events.search_tool
        @test all(events.time_source .== "command-json")

        summary = artifact_search_tool_summary(events)
        @test "lexical" in summary.search_tool
        @test "rg" in summary.search_tool

        optimization_graph = artifact_search_optimization_graph(events)
        @test nv(optimization_graph.graph) > 0
        metrics = artifact_search_optimization_metrics(optimization_graph)
        @test "tool:lexical" in metrics.label
        @test "tool:rg" in metrics.label

        opportunities = artifact_search_optimization_opportunities(events)
        @test "repeat-search" in opportunities.category
        @test "latency-hotspot" in opportunities.category
        @test "lexical-route-optimization" in opportunities.category
        @test "rg-route-optimization" in opportunities.category

        analysis = artifact_search_optimization_analysis(commands)
        @test size(analysis.events, 1) == 4
        @test size(analysis.summary, 1) >= 3
        @test size(analysis.opportunities, 1) >= 4
    end
end
using AspGraphsSearch
using DataFrames
using Dates
using Graphs
using JSON
using Test

@testset "separate lexical and rg algorithm analysis" begin
    commands = DataFrame(
        relative_path = ["lexical-a.json", "lexical-b.json", "rg-a.json", "rg-b.json", "rg-c.json", "pattern-a.json"],
        event_phase = [1, 2, 3, 4, 5, 6],
        event_time = [
            Dates.DateTime(2026, 6, 27, 12, 0, 1),
            Dates.DateTime(2026, 6, 27, 12, 0, 2),
            Dates.DateTime(2026, 6, 27, 12, 0, 3),
            Dates.DateTime(2026, 6, 27, 12, 0, 4),
            Dates.DateTime(2026, 6, 27, 12, 0, 5),
            Dates.DateTime(2026, 6, 27, 12, 0, 6),
        ],
        time_source = fill("command-json", 6),
        language = fill("rust", 6),
        provider = fill("rs-harness", 6),
        method = fill("search", 6),
        operation = ["lexical", "lexical", "rg", "rg", "rg", "search pattern"],
        command_family = fill("provider", 6),
        argv_json = [
            JSON.json(["rs-harness", "search", "lexical", "GraphTurbo", "owner", "--view", "seeds"]),
            JSON.json(["rs-harness", "search", "lexical", "GraphTurbo", "owner", "--view", "seeds"]),
            JSON.json(["rg", "GraphTurbo", "src", "--json"]),
            JSON.json(["rg", "GraphTurbo", "src", "--json"]),
            JSON.json(["rg", "dependency", "schemas", "--json"]),
            JSON.json(["rs-harness", "search", "pattern", "GraphTurbo", "--view", "seeds"]),
        ],
        argv_text = fill("", 6),
        elapsed_ms = [120, 110, 450, 430, 42, 300],
        exit_code = fill(0, 6),
        stdout_bytes = [1000, 980, 2000, 1900, 140, 1200],
        stderr_bytes = fill(0, 6),
    )

    lexical = artifact_lexical_algorithm_analysis(commands)
    rg = artifact_rg_algorithm_analysis(commands)

    @test nrow(lexical.events) == 2
    @test all(lexical.events.search_tool .== "lexical")
    @test nrow(lexical.candidate_pressure) >= 1
    @test "candidate-pruning" in lexical.algorithm_notes.research_axis
    @test "route-promotion" in lexical.algorithm_notes.research_axis
    @test nv(lexical.graph.graph) > 0

    @test nrow(rg.raw_events) == 3
    @test nrow(rg.pattern_events) == 1
    @test nrow(rg.events) == 4
    @test all(rg.raw_events.search_tool .== "rg")
    @test rg.pattern_events.query_terms == ["GraphTurbo"]
    @test nrow(rg.pattern_pressure) >= 2
    @test "pattern-selectivity" in rg.algorithm_notes.research_axis
    @test "structural-query-replacement" in rg.algorithm_notes.research_axis
    @test nv(rg.graph.graph) > 0
end
include("multi_root_strategy_tests.jl")
