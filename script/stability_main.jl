using Validation, CSV

global input = String[]
global d0 = r"S.*_(.*)_.*"  #r"Pre.*_(.*)_.*"
global days = r"S.*_(.*)_(.*)_(.*)_.*"
global order = "TDL"
global type = "Accuracy"
global output = "stability.csv"
global help = false

let i = 0
    while i < length(ARGS)
        i += 1
        if ARGS[i] == "-h"
            global help = true
            break
        elseif  ARGS[i] == "-d0"
            i += 1
            global d0 = Regex(ARGS[i])
        elseif ARGS[i] == "-d"
            i += 1
            global days = Regex(ARGS[i])
        elseif ARGS[i] == "-o"
            i += 1
            global days = ARGS[i]
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

            julia [julia switches] -- stability_main.jl [swithes] [input files]
        
        Swithces (a '*' marks the default value)
            -h                                  Print this message
            -d0 {"S.*_(.*)_.*"*}                Set the identifier for the day0 samples; this will be wrapped in `Regex`. The concentration level is captured in the identifier
            -d {"S.*_(.*)_(.*)_(.*)_.*"*}       Set the identifier for the stability samples; this will be wrapped in `Regex`. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by -o
            -o {TDL*}                           Set the order of captured values from -d identifiers; T is temperature (storage condition); D is storage days; L is concentration level
            -t {Accuracy|"Final Conc."*|Area}   Set the quantification value type
            -s {stability.csv*}                 Set the ouput file
        """)
        return
    end
    stability = StabilityData(reduce(append!, read_data.(input)); d0, days, order, type)
    for temp in keys(stability.accuracy)
        printstyled("Temperature ", temp, color = :blue)
        println()
        for k in keys(stability.accuracy[temp])
            printstyled("Level ", k, "\n", color = :green)
            display(stability.accuracy[temp][k])
            display(stability.rsd[temp][k])
            println()
        end
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
    CSV.write(file, Report(stability))
end

(@__MODULE__() == Main) && main()
