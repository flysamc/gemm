#!/usr/bin/env julia

# Island speciation model using GeMM
#
# Ludwig Leidinger 2018
# <l.leidinger@gmx.net>
#
# Daniel Vedder 2018
# <daniel.vedder@stud-mail.uni-wuerzburg.de>
#
# For a list of options, run `julia islandsim.jl --help`
#
# <MAPFILE> is a textfile containing information about the simulation arena
# Every line describes one patch in the following format:
# <ID> <X-COORDINATE> <Y-COORDINATE> [<TYPE>]

thisDir = pwd() * "/src"
any(path -> path == thisDir, LOAD_PATH) || push!(LOAD_PATH, thisDir)

using GeMM, ArgParse

# Return the default settings. All parameters must be registered here.
function defaultSettings()
    Dict(# general software settings
          "seed" => 1, # for the RNG, seed = 0 -> random seed
          "maps" => nothing, # comma-separated list of map files
          "config" => nothing, # configuration file name
          "fasta" => true, # record fasta data?
          "dest" => string(Dates.today()), # output folder name
          # main model settings
          "linkage" => "random", # gene linkage type
          "nniches" => 2, # number of environmental niches (max. 3)
          "tolerance" => "low", # sequence similarity threshold for reproduction
          "static" => true, # mainland sites don't undergo eco-evolutionary processes
          "mutate" => true, # mutations occur
          "cellsize" => 100, # maximum biomass per cell in tonnes
          # invasion specific settings
          "propagule-pressure" => 0, # TODO
          "disturbance" => 0) # percentage of individuals killed per update per cell
end

function parsecommandline()
    defaults = defaultSettings()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--seed", "-s"
            help = "inital random seed"
            arg_type = Int
            default = defaults["seed"]
        "--maps", "-m"
            help = "list of map files, comma separated"
            arg_type = String
            required = false
        "--config", "-c"
            help = "name of the config file"
            arg_type = String
            required = false
        "--linkage", "-l"
            help = "gene linkage (\"none\", \"random\" or \"full\")"
            arg_type = String
            range_tester = x->in(x,["none", "random", "full"])
            required = false
            default = defaults["linkage"]
        "--nniches", "-n"
            help = "number of environmental niche traits (1 -- 3)"
            arg_type = Int
            range_tester = x -> x > 0 && x <= 3
            required = false
            default = defaults["nniches"]
        "--tolerance", "-t"
            help = "tolerance of sequence identity when reproducing (\"high\", \"evo\", \"low\" or \"none\")"
            arg_type = String
            range_tester = x->in(x,["high", "evo", "low", "none"])
            required = false
            default = defaults["tolerance"]
        "--dest", "-d"
            help = "output directory. Defaults to current date"
            arg_type = String
            required = false
            default = defaults["dest"]
        "--static"
            help = "static mainland. Turns off any dynamics on the continent"
            action = :store_true
        end
    return merge(defaults, parse_args(s))
end

function simulation!(world::Array{Patch,1}, settings::Dict{String,Any}, mapfile::String, seed::Int64, timesteps::Int=1000)
    info("Starting simulation...")
    for t in 1:timesteps
        info("UPDATE $t, population size $(sum(x -> length(x.community), world))")
        (t <= 10 || mod(t, 20) == 0) && writedata(world, mapfile, settings, seed, t)
        establish!(world, settings["nniches"], settings["static"])
        checkviability!(world, settings["static"])
        compete!(world, settings["static"])
        survive!(world, settings["static"])
        disturb!(world, settings["disturbance"], settings["static"])
        grow!(world, settings["static"])
        compete!(world, settings["static"])
        reproduce!(world, settings["static"])
        settings["mutate"] && mutate!(world, settings)
        #TODO invaders = invade!(world, settings["propagule-pressure"])
        #TODO length(colonizers) >= 1 && println("t=$t: colonization by $colonizers")#recordcolonizers(colonizers, mapfile, settings, seed, t)
        colonizers = disperse!(world, settings["static"])
        length(colonizers) >= 1 && println("t=$t: colonization by $colonizers")#recordcolonizers(colonizers, mapfile, settings, seed, t)
    end
end

function runit(settings::Dict{String,Any},seed::Int64=0)
    seed != 0 && srand(seed)
    settings["maps"] = map(x->String(x),split(settings["maps"],","))
    settings["cellsize"] *= 1e6 #convert tonnes to grams
    setupdatadir(settings)
    for i in 1:length(settings["maps"])
        timesteps,maptable = readmapfile(settings["maps"][i])
        i == 1 && (world = createworld(maptable, settings))
        i > 1 && updateworld!(world,maptable,settings["cellsize"])
        simulation!(world, settings, settings["maps"][i], seed, timesteps)
        println("Memory usage:\n\nWorld - $(Base.summarysize(world))")
        println("Individual - $(mean(map(x -> Base.summarysize(x), world[1].community)))")
        writedata(world, settings["maps"][i], settings, seed, -1)
    end
end

## Settings
const allargs = parsecommandline()
if haskey(allargs, "config") && allargs["config"] != nothing
    allargs = parseconfig(allargs["config"], allargs)
end

## Parallel stuff:
const nprocesses = nworkers()
const startseed = allargs["seed"]
const replicates = startseed:startseed+nprocesses-1


@time runit(allargs, startseed)
