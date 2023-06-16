using Validation, CSV

global input = String[]
global matrix = r"Pre.*_(.*)_.*"
global stds = r"Post.*_(.*)_.*"
global type = "Final Conc."
global output = "me.csv"
global help = false

let i = 0
    while i < length(ARGS)
        i += 1
        if ARGS[i] == "-h"
            global help = true
            break
        elseif  ARGS[i] == "-matrix"
            i += 1
            global matrix = Regex(ARGS[i])
        elseif ARGS[i] == "-stds"
            i += 1
            global stds = Regex(ARGS[i])
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

            julia [julia switches] -- me_main.jl [swithes] [input files]
        
        Swithces (a '*' marks the default value)
            -h                                  Print this message
            -matrix {"Pre.*_(.*)_.*"*}          Set the identifier for the samples; this will be wrapped in `Regex`.
            -stds {"Post.*_(.*)_.*"*}           Set the identifier for the standard solutions; this will be wrapped in `Regex`.
            -t {Accuracy|"Final Conc."*|Area}   Set the quantification value type
            -s {me.csv*}                        Set the ouput file
        """)
        return
    end
    me = MEData(reduce(append!, read_data.(input)); matrix, stds, type)
    level = keys(me.data)
    for k in level
        printstyled("Level ", k, "\n", color = :green)
        display(me.data[k])
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
    CSV.write(file, Report(me.data))
end

(@__MODULE__() == Main) && main()