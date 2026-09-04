using Documenter, IFE

makedocs(;
    modules=[IFE],
    sitename="IFE",
    authors="Min-Gu Yoo",
    # Nothing is exported (everything is used as `IFE.x`, like FUSE), so
    # `:exports` would check an empty set. The API page lists the surface
    # explicitly.
    checkdocs=:none,
    # Declared rather than sniffed from `git remote`, so the docs build works
    # from a clone that has no remote configured.
    remotes=Dict(
        dirname(@__DIR__) => (Documenter.Remotes.GitHub("ProjectTorreyPines", "IFE.jl"), "master")),
    format=Documenter.HTML(;
        canonical="https://projecttorreypines.github.io/IFE.jl",
        edit_link="master",
        size_threshold=nothing,
        size_threshold_warn=nothing),
    pages=[
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    # Not `warnonly`: the `@example` block on the home page runs the full actor
    # chain, so a stale example breaks the build rather than shipping wrong code.
)

deploydocs(;
    repo="github.com/ProjectTorreyPines/IFE.jl.git",
    target="build",
    branch="gh-pages",
    devbranch="master",
    versions=["stable" => "v^", "v#.#"]
)
