#!/usr/bin/env julia
## contains all custom types necessary for eco-evo-env speciation island model

## NOTE: all functions: make methods for ind/pop/island/world level!!!!

using Distributions

const boltz = 1.38064852e-23 #  J/K = m2⋅kg/(s2⋅K)
const act = 1e-19 # activation energy /J, ca. 0.63eV - Brown et al. 2004
const normconst = 1e10 # normalization constant to get biologically realistic orders of magnitude

## Types:

mutable struct Trait
    name::String
    value::Float64 # numerical value
    ##    strength::Float64 # mutation strength
    codedby::Int64
    active::Bool
end

mutable struct Gene
    sequence::Array{Char,1} # contains gene base code
    id::String # gene identifier
    codes::Array{Trait,1}
end

mutable struct Chromosome #CAVE! mutable?
    genes::Array{Gene,1} # 1D array of genes
    maternal::Bool # parental origin of chromosome
end


mutable struct Individual
    genome::Array{Chromosome,1} # genome = 2D array of chromosomes (>=1 sets)
    traits::Dict{String,Float64}
    age::Int64
    isnew::Bool # indicator whether individual is new to a patch or has already dispersed etc.
    fitness::Float64 # reproduction etc. scaling factor representing life history
    size::Float64 # body size/mass -> may replace stage.
end

mutable struct Patch
    community::Array{Individual,1} # holds the population (1D) of prob not: present species (2nd D)
    altitude::Float64 # altitude: corresponds to T
    nichea::Float64 # additional niches,
    nicheb::Float64 # e.g. precipitation
    area::Float64
    location::Tuple{Float64,Float64}
end


## methods:
function compete!(patch::Patch)
    while sum(map(x->x.size,patch.community)) > patch.area # occupied area larger than available
        victim = rand(1:size(patch.community,1))
        splice!(patch.community, victim)
    end
end

function meiosis(genome::Array{Chromosome,1},maternal::Bool) # TODO: include further dynamics, errors...
    firstset = find(x->x.maternal,genome)
    secondset = find(x->!x.maternal,genome)
    size(firstset,1) != size(secondset,1) && return Chromosome[] # CAVE: more elegant solution...
    gameteidxs = []
    for i in eachindex(firstset)
        push!(gameteidxs,rand([firstset[i],secondset[i]]))
    end
    gamete = deepcopy(genome[gameteidxs]) #TODO somewhere here: crossing over!
    map(x->x.maternal=maternal,gamete)
    gamete
end
    

function reproduce!(patch::Patch) #TODO: refactorize!
    idx = 1
    temp = patch.altitude
    while idx <= size(patch.community,1)
        hasrepprob = haskey(patch.community[idx].traits,"repprob")
        hasreptol = haskey(patch.community[idx].traits,"reptol")
        hasreprate = haskey(patch.community[idx].traits,"reprate")
        hasseedsize = haskey(patch.community[idx].traits,"seedsize")
        hasmutprob = haskey(patch.community[idx].traits,"mutprob")
        if !hasrepprob || !hasreprate || !hasreptol || !hasmutprob || !hasseedsize 
            splice!(patch.community, idx)
            idx -= 1
        else
            repprob = patch.community[idx].traits["repprob"]
            if !patch.community[idx].isnew && rand() <= repprob
                currentmass = patch.community[idx].size
                seedsize = patch.community[idx].traits["seedsize"]
                if currentmass >= 2 * seedsize > 0 #CAVE: set rule for this, now arbitrary -> reprod. size?
                    meanoffs = patch.community[idx].traits["reprate"]
                    reptol = patch.community[idx].traits["reptol"]
                    mass = patch.community[idx].size
                    metaboffs =  meanoffs * currentmass^(-1/4) * exp(-act/(boltz*temp)) * normconst
                    noffs = rand(Poisson(metaboffs))
                    if sexualreproduction
                        posspartners = find(x->(1/reptol)*mass>=x.size>=reptol*mass,patch.community)
                        partneridx = rand(posspartners)
                        while size(posspartners,1) > 1 && partneridx == idx #CAVE: unless self-repr. is allowed
                            partneridx = rand(posspartners)
                        end
                        partnergenome = meiosis(patch.community[partneridx].genome, false) #CAVE: maybe move inside offspring loop?
                        mothergenome = meiosis(patch.community[idx].genome, true)
                        
                        for i in 1:noffs
                            (size(partnergenome,1) < 1 || size(mothergenome,1) < 1) && continue
                            genome = deepcopy([partnergenome...,mothergenome...])
                            activategenes!(genome)
                            traits = chrms2traits(genome)
                            age = 0
                            isnew = true
                            fitness = 1.0
                            newsize = seedsize
                            ind = Individual(genome,traits,age,isnew,fitness,newsize)
                            !haskey(ind.traits,"mutprob") && continue
                            mutate!(ind, patch.altitude)
                            push!(patch.community,ind)
                        end
                    end
                end
            end
        end
        idx += 1
    end
end

function mutate!(ind::Individual, temp::Float64)
    prob = ind.traits["mutprob"]
    for chr in ind.genome
        for gene in chr.genes
            for i in eachindex(gene.sequence)
                if rand() <= prob*exp(-act/(boltz*temp)) * normconst
                    newbase = rand(collect("acgt"),1)[1]
                    while newbase == gene.sequence[i]
                        newbase = rand(collect("acgt"),1)[1]
                    end
                    gene.sequence[i] = newbase
                    for trait in gene.codes
                        trait.value == 0 && (trait.value = rand(Normal(0,0.01)))
                        newvalue = trait.value + rand(Normal(0, trait.value/mutscaling)) # new value for trait
                        (newvalue > 1 && contains(trait.name,"prob")) && (newvalue=1)
                        (newvalue > 1 && contains(trait.name,"reptol")) && (newvalue=1)
                        newvalue < 0 && (newvalue=abs(newvalue))
                        while newvalue == 0 #&& contains(trait.name,"mut")
                            newvalue = trait.value + rand(Normal(0, trait.value/mutscaling))
                        end
                        trait.value = newvalue
                    end
                end
            end
        end
    end
    traitdict = chrms2traits(ind.genome)
    ind.traits = traitdict
end

function grow!(patch::Patch)
    temp = patch.altitude
    idx = 1
    while idx <= size(patch.community,1)
        hasgrowthrate = haskey(patch.community[idx].traits,"growthrate")
        if !hasgrowthrate
            splice!(patch.community, idx)
            idx -= 1
        else
            if !patch.community[idx].isnew
                growthrate = patch.community[idx].traits["growthrate"]
                mass = patch.community[idx].size
                newmass = growthrate * mass^(-1/4) * exp(-act/(boltz*temp)) * normconst #CAVE: what to do when negative growth? -> emergent maximum body size!
                if newmass > 0 && mass > 0
                    patch.community[idx].size = newmass
                else
                    splice!(patch.community, idx)
                    idx -= 1
                end
            end
        end
        idx += 1
    end
end

function age!(patch::Patch)
    temp = patch.altitude
    idx = 1
    while idx <= size(patch.community,1)
        hasageprob = haskey(patch.community[idx].traits,"ageprob")
        if !hasageprob
            splice!(patch.community, idx)
            idx -= 1
        else
            if !patch.community[idx].isnew
                ageprob = patch.community[idx].traits["ageprob"]
                mass = patch.community[idx].size
                dieprob = ageprob * mass^(-1/4) * exp(-act/(boltz*temp)) * normconst
                if rand() > (1-dieprob) * patch.community[idx].fitness
                    splice!(patch.community, idx)
                    idx -= 1
                else
                    patch.community[idx].age += 1
                end
            end
        end
        idx += 1
    end
end


function establish!(patch::Patch) #TODO!
    temp = patch.altitude
    idx = 1
    while idx <= size(patch.community,1)
        hastemptol = haskey(patch.community[idx].traits,"temptol")
        hastempopt = haskey(patch.community[idx].traits,"tempopt")
        if !hastemptol || !hastempopt
            splice!(patch.community, idx)
            idx -= 1
        else
            if patch.community[idx].isnew
                tempopt = patch.community[idx].traits["tempopt"]
                temptol = patch.community[idx].traits["temptol"]
                if abs(temp-tempopt) > temptol
                    splice!(patch.community, idx)
                    idx -= 1
                else
                    patch.community[idx].isnew = false
                    fitness = 1 - (abs(temp-tempopt))/temptol
                    fitness > 1 && (fitness = 1)
                    fitness < 0 && (fitness = 0)
                    patch.community[idx].fitness = fitness
                end
            end
        end
        idx += 1
    end
end

#TODO: Dispersal

function createtraits(traitnames::Array{String,1})
    traits = Trait[]
    for name in traitnames
        if contains(name,"rate")
            push!(traits,Trait(name,rand()*10,0,true))
        elseif contains(name, "temp") && contains(name, "opt")
            push!(traits,Trait(name,rand(Normal(298,5)),0,true)) #CAVE: code values elsewhere?
        elseif contains(name, "tol") && !contains(name, "rep")
            push!(traits,Trait(name,abs(rand(Normal(0,5))),0,true)) #CAVE: code values elsewhere?
        elseif contains(name, "mut")
            push!(traits,Trait(name,abs(rand(Normal(0,0.01))),0,true)) #CAVE: code values elsewhere?
        else
            push!(traits,Trait(name,rand(),0,true))
        end
    end
    traits
end

function creategenes(ngenes::Int64,traits::Array{Trait,1})
    genes = Gene[]
    viable = false
    while !viable
        for trait in traits
            trait.codedby = 0
        end
        genes = Gene[]
        for gene in 1:ngenes
            sequence = collect("acgt"^5) # arbitrary start sequence
            id = randstring(8)
            codesfor = Trait[]
            append!(codesfor,rand(traits,rand(Poisson(0.5))))
            for trait in codesfor
                trait.codedby += 1
            end
            push!(genes,Gene(sequence,id,codesfor))
        end
        viable = true
        for trait in traits
            trait.codedby == 0 && (viable = false) # make sure every trait is coded by at least 1 gene
        end
    end
    genes
end

function createchrs(nchrs::Int64,genes::Array{Gene,1})
    ngenes=size(genes,1)
    if nchrs>1
        chrsplits = sort(rand(1:ngenes,nchrs-1))
        chromosomes = Chromosome[]
        for chr in 1:nchrs
            if chr==1 # first chromosome
                push!(chromosomes, Chromosome(genes[1:chrsplits[chr]],rand([false,true])))
            elseif chr==nchrs # last chromosome
                push!(chromosomes, Chromosome(genes[(chrsplits[chr-1]+1):end],rand([false,true])))
            else
                push!(chromosomes, Chromosome(genes[(chrsplits[chr-1]+1):chrsplits[chr]],rand([false,true])))
            end
        end
    else # only one chromosome
        chromosomes = [Chromosome(genes,rand([false,true]))]
    end
    secondset = deepcopy(chromosomes)
    for chrm in secondset
        chrm.maternal = !chrm.maternal
    end
    append!(chromosomes,secondset)
    chromosomes
end

function activategenes!(chrms::Array{Chromosome,1})
    genes = Gene[]
    for chrm in chrms
        append!(genes,chrm.genes)
    end
    traits = Trait[]
    for gene in genes
        append!(traits,gene.codes)
    end
    traits = unique(traits)
    traitnames = map(x->x.name,traits)
    traitnames = unique(traitnames)
    for name in traitnames
        idxs = find(x->x.name==name,traits)
        map(x->traits[x].active = false,idxs)
        map(x->traits[x].active = true,rand(idxs))
    end
end

function chrms2traits(chrms::Array{Chromosome,1})
    genes = Gene[]
    for chrm in chrms
        append!(genes,chrm.genes)
    end
    traits = Trait[]
    for gene in genes
        append!(traits,gene.codes)
    end
    traits = unique(traits)
    traitdict = Dict{String,Float64}()
    for trait in traits
        trait.active && (traitdict[trait.name] = trait.value)
    end
    traitdict
end

function checkviability!(patch::Patch) # may consider additional rules... # maybe obsolete anyhow...
    idx=1
    while idx <= size(patch.community,1)
        kill = false
        patch.community[idx].size <= 0 && (kill = true)
        0 in collect(values(patch.community[idx].traits)) && (kill = true)
        if kill
            splice!(patch.community,idx) # or else kill it
            idx -= 1
        end
        idx += 1
    end
end

function checkviability!(world::Array{Patch,1})
    for patch in world
        checkviability!(patch) # pmap(checkviability!,patch) ???
    end
end

function establish!(world::Array{Patch,1})
    for patch in world
        establish!(patch) # pmap(!,patch) ???
    end
end

function age!(world::Array{Patch,1})
    for patch in world
        age!(patch) # pmap(!,patch) ???
    end
end

function grow!(world::Array{Patch,1})
    for patch in world
        grow!(patch) # pmap(!,patch) ???
    end
end

function disperse!(world::Array{Patch,1})
    for patch in world
        idx = 1
        while idx <= size(patch.community,1)
            hasdispmean = haskey(patch.community[idx].traits,"dispmean")
            hasdispprob = haskey(patch.community[idx].traits,"dispprob")
            hasdispshape = haskey(patch.community[idx].traits,"dispshape")
            if !hasdispmean || !hasdispprob || !hasdispshape
                splice!(patch.community,idx)
                idx -= 1
            elseif !patch.community[idx].isnew && rand() <= patch.community[idx].traits["dispprob"]
                dispmean = patch.community[idx].traits["dispmean"]
                dispshape = patch.community[idx].traits["dispshape"]
                patch.community[idx].isnew = true
                indleft = splice!(patch.community,idx)
                xdir = rand([-1,1]) * rand(Logistic(dispmean,dispshape))/sqrt(2) # scaling so that geometric mean
                ydir = rand([-1,1]) * rand(Logistic(dispmean,dispshape))/sqrt(2) # follows original distribution
                xdest = patch.location[1]+xdir # CAVE: might be other way around + border conditions
                ydest = patch.location[1]+ydir # CAVE: might be other way around + border conditions
                targets = unique([(floor(xdest),floor(ydest)),(ceil(xdest),floor(ydest)),(ceil(xdest),ceil(ydest)),(floor(xdest),ceil(ydest))])
                possdests = find(x->in(x.location,targets),world)
                if size(possdests,1) > 0 # if no viable target patch, individual dies
                    size(possdests,1) > 1 ? (destination=rand(possdests)) : (destination = possdests[1])
                    push!(world[destination].community,indleft)
                end
                idx -= 1
            end
            idx += 1
        end
    end
end

function compete!(world::Array{Patch,1})
    for patch in world
        compete!(patch) # pmap(!,patch) ???
    end
end

function reproduce!(world::Array{Patch,1}) # TODO: requires certain amount of resource/bodymass dependent on seedsize!
    for patch in world
        reproduce!(patch) # pmap(!,patch) ???
    end
end


function genesis(ninds::Int64=1000, meangenes::Int64=20, meanchrs::Int64=5,
                 traitnames::Array{String,1} = ["ageprob",
                                                "dispmean",
                                                "dispprob",
                                                "dispshape",
                                                "growthrate",
                                                "mutprob",
                                                "repprob",
                                                "reprate",
                                                "reptol",
                                                "seedsize",
                                                #"sexprob",
                                                "temptol",
                                                "tempopt"]) # minimal required traitnames
    community = Individual[]
    for ind in 1:ninds
        ngenes = rand(Poisson(meangenes))
        nchrs = rand(Poisson(meanchrs))
        traits = createtraits(traitnames)
        genes = creategenes(ngenes,traits)
        chromosomes = createchrs(nchrs,genes)
        traitdict = chrms2traits(chromosomes)
        push!(community, Individual(chromosomes,traitdict,0,true,1.0,rand()))
    end
    community
end



## Test stuff:
##############
testpatch=Patch(genesis(),293,0.5,0.5,100,(0,0))
startpatch=deepcopy(testpatch)
const timesteps=1000 #Int64(round(parse(ARGS[1])))
const mutscaling=50#parse(ARGS[2])
const sexualreproduction = true
for i = 1:timesteps
    checkviability!(world)
    map(x->size(x.community,1),world)
    establish!(world)
    map(x->size(x.community,1),world)
    age!(world)
    map(x->size(x.community,1),world)
    grow!(world)
    map(x->size(x.community,1),world)
    disperse!(world)
    map(x->size(x.community,1),world)
    compete!(world)
    map(x->size(x.community,1),world)
    reproduce!(world) # TODO: requires certain amount of resource/bodymass dependent on seedsize!
    map(x->size(x.community,1),world)
end
map(x->size(x.community,1),world)
histogram(map(x->x.size,world[1].community))


mean(map(x->x.traits["mutprob"],world[1].community))

mean(map(x->x.traits["repprob"],world[1].community))

mean(map(x->x.traits["ageprob"],world[1].community))

mean(map(x->x.traits["temptol"],world[1].community))

mean(map(x->x.traits["reprate"],world[1].community))

mean(map(x->x.traits["growthrate"],world[1].community))

mean(map(x->x.traits["tempopt"],world[1].community))

mean(map(x->x.traits["seedsize"],world[1].community))

minimum(map(x->x.traits["seedsize"],world[1].community))

maximum(map(x->x.traits["seedsize"],world[1].community))