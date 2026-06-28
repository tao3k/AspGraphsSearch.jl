using Pkg

package_root = dirname(@__DIR__)

cd(package_root) do
    Pkg.activate(".")
    Pkg.develop(path="../ScienceResearch.jl")
    Pkg.instantiate()
end

using PlutoStaticHTML
using ScienceResearch

config = NotebookHtmlBuildConfig(
    package_root=package_root,
    notebook_dir=joinpath(package_root, "notebooks"),
    output_dir=joinpath(package_root, "public"),
    previous_dir=joinpath(package_root, ".pluto-cache"),
    project_title="ASP Graph Search",
    max_concurrent_runs=1,
    use_distributed=false,
)

Base.invokelatest(build_notebook_html, config)
