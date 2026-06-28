using AspGraphsSearch
using DataFrames
using Graphs
using JSON
using Test

function write_strategy_command_artifact(path::AbstractString; method::String, language::String, provider::String, argv::Vector{String}, started_ms::Int)
    mkpath(dirname(path))
    payload = Dict(
        "schemaId" => "agent.semantic-protocols.test-command.v1",
        "method" => method,
        "languageId" => language,
        "providerId" => provider,
        "eventTimestampMs" => started_ms,
        "providerCommands" => [
            Dict(
                "argv" => argv,
                "languageId" => language,
                "providerId" => provider,
                "operation" => method,
                "elapsedMs" => 17,
                "exitCode" => 0,
                "stdoutBytes" => 41,
                "stderrBytes" => 0,
                "startedAtMs" => started_ms,
                "endedAtMs" => started_ms + 17,
            ),
        ],
    )
    write(path, JSON.json(payload))
    return path
end

@testset "rg coverage reports searchable scopes without rg evidence" begin
    mktempdir() do repo_root
        workspace_artifacts = joinpath(repo_root, ".cache", "agent-semantic-protocol", "artifacts", "search")
        gerbil_artifacts = joinpath(
            repo_root,
            "languages",
            "gerbil-scheme-language-project-harness",
            ".cache",
            "agent-semantic-protocol",
            "artifacts",
            "search",
        )

        write_strategy_command_artifact(
            joinpath(workspace_artifacts, "rust-owner.json");
            method = "search owner",
            language = "rust",
            provider = "rust",
            argv = ["asp", "rust", "search", "owner", "src/lib.rs"],
            started_ms = 1_000,
        )
        write_strategy_command_artifact(
            joinpath(gerbil_artifacts, "gerbil-rg.json");
            method = "shell command",
            language = "gerbil-scheme",
            provider = "gerbil-scheme",
            argv = ["rg", "define", "src"],
            started_ms = 1_100,
        )

        dataset = artifact_research_dataset_from_repo(repo_root)
        rg = artifact_rg_algorithm_analysis(dataset.commands)

        rust_rows = rg.coverage[(rg.coverage.artifact_scope .== "workspace") .& (rg.coverage.language .== "rust"), :]
        @test nrow(rust_rows) == 1
        @test only(rust_rows.rg_events) == 0
        @test only(rust_rows.rg_coverage_status) == "search-without-rg-evidence"

        gerbil_scope = "language:gerbil-scheme-language-project-harness"
        gerbil_rows = rg.coverage[(rg.coverage.artifact_scope .== gerbil_scope) .& (rg.coverage.language .== "gerbil-scheme"), :]
        @test nrow(gerbil_rows) == 1
        @test only(gerbil_rows.raw_rg_events) == 1
        @test only(gerbil_rows.rg_coverage_status) == "rg-evidence"

        @test any(rg.opportunities.category .== "rg-coverage-gap")
    end
end

@testset "multi-root artifact aggregation and graph strategy analysis" begin
    mktempdir() do repo
        root_artifacts = joinpath(repo, ".cache", "agent-semantic-protocol", "artifacts", "prompt-output")
        rust_artifacts = joinpath(repo, "languages", "rust", ".cache", "agent-semantic-protocol", "artifacts", "prompt-output")

        write_strategy_command_artifact(
            joinpath(root_artifacts, "graph-router-command.json");
            method="search graph-router",
            language="rust",
            provider="rs-harness",
            argv=["asp", "rust", "search", "graph-router", "semantic graph facts"],
            started_ms=1_780_000_000_000,
        )
        write_strategy_command_artifact(
            joinpath(rust_artifacts, "graph-reasoning-command.json");
            method="search graph-reasoning",
            language="rust",
            provider="rs-harness",
            argv=["asp", "rust", "search", "graph-reasoning", "router confidence"],
            started_ms=1_780_000_001_000,
        )

        roots = artifact_discover_roots(repo)
        @test length(roots) == 2

        dataset = artifact_research_dataset_from_repo(repo)
        @test Set(dataset.artifact_roots.artifact_scope) == Set(["workspace", "language:rust"])
        @test all(dataset.artifact_roots.json_file_count .== 1)
        @test nrow(dataset.commands) == 2
        @test Set(dataset.commands.artifact_scope) == Set(["workspace", "language:rust"])
        @test nv(dataset.flow.graph) > 0

        strategy = artifact_search_strategy_analysis(dataset.commands)
        @test Set(strategy.events.strategy) == Set(["graph-router", "graph-reasoning"])
        @test Set(strategy.events.strategy_family) == Set(["graph-strategy"])
        @test nrow(strategy.summary) == 2
        @test nv(strategy.graph.graph) > 0
        @test ne(strategy.graph.graph) > 0
        @test any(label -> label == "strategy:graph-router", strategy.graph.labels)
        @test any(label -> label == "strategy:graph-reasoning", strategy.graph.labels)
        @test any(row -> row.category == "missing-graph-strategy-evidence" && row.target == "semantic-graph", eachrow(strategy.opportunities))
    end
end
