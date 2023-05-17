using Validation, CSV

global input = String[]
global id = r"Pre.*_(.*)_.*"
global type = "Accuracy"
global ouput = "accuracy_precision.csv"
global help = false

let i = 0
    while i < length(ARGS)
        i += 1
        if ARGS[i] == "-h"
            global help = true
            break
        elseif ARGS[i] == "-i"
            i += 1
            global id = Regex(ARGS[i])
        elseif ARGS == "-t"
            i += 1
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

            julia [julia switches] -- ap_main.jl [swithes] [input files]
        
        Swithces (a '*' marks the default value)
            -h                                  Print this message
            -i {"Pre.*_(.*)_.*"*}               Set the identifier for the AP experiment samples; this will be wrapped in `Regex`.
            -t {Accuracy*|"Final Conc."|Area}   Set the quantification value type
            -s {accuracy_precision.csv*}        Set the ouput file
        """)
        return
    end
    ap = ap_report(read_data.(input)...; id, type)
    level = keys(ap.final)
    printstyled("Daily: ", color = :blue)
    println()
    for k in level
        printstyled("Level ", k, "\n", color = :green)
        display(ap.daily.accuracy[k])
        display(ap.daily.rsd[k])
        println()
    end
    printstyled("Final: ", color = :blue)
    println()
    for k in level
        printstyled("Level ", k, "\n", color = :green)
        display(ap.final[k])
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
    CSV.write(file, flatten_ap(ap))
end

(@__MODULE__() == Main) && main()
