using Validation, CSV

global input = String[]
global id = r"PooledQC"
global type = "Final Conc."
global output = "qc.csv"
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
            global type = ARGS[i]
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

            julia [julia switches] -- qc_main.jl [swithes] [input files]
        
        Swithces (a '*' marks the default value)
            -h                                  Print this message
            -i {PooledQC*}                      Set the identifier for the AP experiment samples; this will be wrapped in `Regex`.
            -t {Accuracy|"Final Conc."*|Area}   Set the quantification value type
            -s {accuracy_precision.csv*}        Set the ouput file
        """)
        return
    end
    qc = qc_report(reduce(append!, read_data.(input)); id, type)
    display(qc)
    println()
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
    CSV.write(file, qc)
end

(@__MODULE__() == Main) && main()
