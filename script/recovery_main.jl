using Validation, CSV

global input = String[]
global pre = r"Pre.*_(.*)_.*"
global post = r"Post.*_(.*)_.*"
global type = "Final Conc."
global output = "recovery.csv"
global help = false

let i = 0
    while i < length(ARGS)
        i += 1
        if ARGS[i] == "-h"
            global help = true
            break
        elseif  ARGS[i] == "-pre"
            i += 1
            global pre = Regex(ARGS[i])
        elseif ARGS[i] == "-post"
            i += 1
            global post = Regex(ARGS[i])
        elseif ARGS == "-t"
            global type = ARGS[i]
        elseif ARGS[i] == "-s"
            i += 1
            global output = ARGS[i]
        else
            any(x -> occursin("-", x), ARGS[i:end]) && throw(ArgumentError("Invalid switches position"))
            global input = ARGS[i:end]
            break
        end
    end
end

function main()
    if help
        println(stdout, 
        """

            julia [julia switches] -- recovery_main.jl [swithes] [input files]
        
        Swithces (a '*' marks the default value)
            -h                                  Print this message
            -pre {"Pre.*_(.*)_.*"*}             Set the identifier for the prespiked samples; this will be wrapped in `Regex`.
            -post {"Post.*_(.*)_.*"*}           Set the identifier for the postspiked samples; this will be wrapped in `Regex`.
            -t {Accuracy|"Final Conc."*|Area}   Set the quantification value type
            -s {recovery.csv*}                  Set the ouput file
        """)
        return
    end
    recovery = recovery_report(reduce(append!, read_data.(input)); pre, post, type)
    level = keys(recovery)
    for k in level
        printstyled("Level ", k, "\n", color = :green)
        display(recovery[k])
        println()
    end
    i = 0
    file = output
    name = split(basename(output), ".csv")[1]
    dir = dirname(file)
    dir = isempty(dir) ? pwd() : dir
    filename = basename(file)
    while filename in readdir(dir)
        i += 1
        filename = join([name, "($i).csv"], "")
        file = joinpath(dir, filename)
    end
    CSV.write(file, flatten_recovery(recovery))
end

(@__MODULE__() == Main) && main()