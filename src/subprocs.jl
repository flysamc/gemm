# Subsidiary functions for GeMM

function meiosis(genome::Array{Chromosome,1},maternal::Bool) # TODO: include further dynamics, errors...
    firstset = find(x->x.maternal,genome)
    secondset = find(x->!x.maternal,genome)
    size(firstset,1) != size(secondset,1) && return Chromosome[] # CAVE: more elegant solution...
    gameteidxs = []
    for i in eachindex(firstset)
        push!(gameteidxs,rand([firstset[i],secondset[i]]))
    end
    gamete = Chromosome[]
    for i in gameteidxs
        push!(gamete, Chromosome(genome[i].genes, maternal))
    end
    deepcopy(gamete)
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
    traitdict = Dict{String,Float64}()
    for traitname in unique(map(x->x.name,traits))
        traitdict[traitname] = mean(map(x->x.value,filter(x->x.name==traitname,traits)))
    end
    traitdict
end

function traitsexist(ind::Individual, traitnames::Array{String, 1})
    for trait in traitnames
        !haskey(ind.traits, trait) && return false
    end
    true
end

function gausscurve(b::Float64, c::Float64, x::Float64, a::Float64=1.0)
    if c != 0 && a != 1.0
        a = 1 / (c * sqrt(2 * pi))
        y = a * exp(-(x-b)^2/(2*c^2))
    elseif c != 0
        y = a * exp(-(x-b)^2/(2*c^2))
    else
        y = 0
    end
end

"""
    findisland(w)
within world `w`, find out in which direction from the continent the island(s) lie(s).
"""
function findisland(world::Array{Patch,1})
    xmin = minimum(map(x->x.location[1],world))
    xmax = maximum(map(x->x.location[1],world))
    ymin = minimum(map(x->x.location[2],world))
    ymax = maximum(map(x->x.location[2],world))
    westernborder = filter(x->x.location[1]==xmin,world)
    northernborder = filter(x->x.location[2]==ymax,world)
    easternborder = filter(x->x.location[1]==xmax,world)
    southernborder = filter(x->x.location[2]==ymin,world)
    if all(map(x->x.isisland,westernborder))
        return "west"
    elseif all(map(x->x.isisland,northernborder))
        return "north"
    elseif all(map(x->x.isisland,easternborder))
        return "east"
    elseif all(map(x->x.isisland,southernborder))
        return "south"
    else
        return "none"
    end
end

"""
    checkborderconditions!(w, x, y)
check if coordinates `x` and `y` lie within world `w` and correct if not,
considering defined border conditions.
"""
function checkborderconditions!(world::Array{Patch,1},xdest::Float64,ydest::Float64)
    xmin = minimum(map(x->x.location[1],world))
    xmax = maximum(map(x->x.location[1],world))
    ymin = minimum(map(x->x.location[2],world))
    ymax = maximum(map(x->x.location[2],world))
    xrange = xmax - xmin + 1 # we're counting cells!
    yrange = ymax - ymin + 1 # we're counting cells!
    xshift = xdest - xmin + 1 # 1-based count of cells
    yshift = ydest - ymin + 1 # 1-based count of cells
    xshift > 0 ? outofx = abs(xshift) : outofx = abs(xshift) + 1
    while outofx > xrange
        outofx -= xrange
    end
    outofx -= 1
    yshift > 0 ? outofy = abs(yshift) : outofy = abs(yshift) + 1
    while outofy > yrange
        outofy -= yrange
    end
    outofy -= 1
    islanddirection = findisland(world::Array{Patch,1})
    if islanddirection == "west"
        xdest > xmax && (xdest = xmax - outofx) # east: reflective
        ydest < ymin && (ydest = ymax - outofy) # south: periodic
        ydest > ymax && (ydest = ymin + outofy) # north: periodic
    elseif islanddirection == "north"
        ydest < ymin && (ydest = ymin + outofy) # south: reflective
        xdest < xmin && (xdest = xmax - outofx) # west: periodic
        xdest > xmax && (xdest = xmin + outofx) # east: periodic
    elseif islanddirection == "east"
        xdest < xmin && (xdest = xmin + outofx) # west: reflective
        ydest < ymin && (ydest = ymax - outofy) # south: periodic
        ydest > ymax && (ydest = ymin + outofy) # north: periodic
    elseif islanddirection == "south"
        ydest > ymax && (ydest = ymax + outofy) # north: reflective
        xdest < xmin && (xdest = xmax - outofx) # west: periodic
        xdest > xmax && (xdest = xmin + outofx) # east: periodic
    else
        ydest > ymax && (ydest = ymin + outofy) # north: periodic
        xdest > xmax && (xdest = xmin + outofx) # east: periodic
        ydest < ymin && (ydest = ymax - outofy) # south: periodic
        xdest < xmin && (xdest = xmax - outofx) # west: periodic
    end
    xdest,ydest
end

function iscompatible(mate::Individual, ind::Individual)
    tolerance = ind.traits["reptol"]
    indgene = ""
    for chrm in ind.genome
        for gene in chrm.genes
            any(x -> x.name == "compat", gene.codes) && (indgene *= gene.sequence)
        end
    end
    mategene = ""
    for chrm in mate.genome
        for gene in chrm.genes
            any(x -> x.name == "compat", gene.codes) && (mategene *= gene.sequence)
        end
    end
    basediffs = 0
    for i in eachindex(indgene)
        try
            indgene[i] != mategene[i] && (basediffs += 1) # alternatively use bioinformatics tools
        catch # e.g., in case of differently long genes
            basediffs += 1
        end
    end
    seqidentity = 1 - (basediffs / length(indgene))
    seqidentity < tolerance && return false # CAVE: maybe compare w/ indgenome?
    true
end

function findposspartners(world::Array{Patch,1}, ind::Individual, location::Tuple{Int64, Int64})
    ind.isnew = true
    radius = floor(ind.traits["repradius"] + 0.5) # CAVE: to account for cell width ... or not??
    coordinates = Tuple[]
    for x = -radius:radius, y = -radius:radius
        sqrt(x^2 + y^2) <= radius && push!(coordinates, (x + location[1], y + location[2]))
    end
    coordinates = map(k -> checkborderconditions!(world, k[1], k[2]), coordinates)
    order = map(x -> x.^2, coordinates) |> x -> map(sum, x) |> x -> map(sqrt, x) |> sortperm
    coordinates = coordinates[order]
    posspartners = Individual[]
    idx = 1 # check patches in order of increasing distance
    while length(posspartners) == 0
        idx > length(coordinates) && break
        targetpatch = filter(l -> l.location == coordinates[idx], world)
        length(targetpatch) >= 1 ? community = targetpatch[1].community : community = Individual[]
        append!(posspartners, community)
        filter!(k -> k.age > 0, posspartners)
        filter!(k -> k.lineage == ind.lineage, posspartners)
        filter!(k -> traitsexist(k, ["repsize"]), posspartners)
        filter!(k -> k.size >= k.traits["repsize"], posspartners)
        filter!(k -> !k.isnew, posspartners) # filter out mating individual
        filter!(k -> iscompatible(k, ind), posspartners)
        idx += 1
    end
    ind.isnew = false
    posspartners
end

function createtraits(traitnames::Array{String,1}, settings::Dict{String,Any}) #TODO: this is all very ugly. (case/switch w/ v. 2.0+?)
    traits = Trait[]
    seedsize = exp(-7 + 20 * rand()) # corresponds to 1mg to 22kg
    repsize = exp(0 + 17 * rand()) # 1g to 24t
    while repsize <= seedsize
        seedsize = exp(-7 + 20 * rand())
        repsize = exp(0 + 17 * rand())
    end
    for name in traitnames
        if contains(name,"rate")
            push!(traits,Trait(name,rand()*100))
        elseif contains(name,"dispshape")
            push!(traits, Trait(name, rand() * maxdispmean))
        elseif contains(name, "tempopt")
            push!(traits,Trait(name, rand() * 40 + 273)) #CAVE: code values elsewhere?
        elseif contains(name, "temptol")
            push!(traits,Trait(name,rand()*5)) #CAVE: code values elsewhere?
        elseif contains(name, "mut")
            mutationrate == 0 ? push!(traits,Trait(name,rand())) : push!(traits,Trait(name,mutationrate)) #CAVE: code values elsewhere?
        elseif contains(name, "repsize")
            push!(traits,Trait(name,repsize)) #CAVE: code values elsewhere?
        elseif contains(name, "seedsize")
            push!(traits,Trait(name,seedsize)) #CAVE: code values elsewhere?
        elseif contains(name, "precopt")
            push!(traits, Trait(name, rand() * 10))
        elseif contains(name, "prectol")
            push!(traits, Trait(name, rand()))
        elseif contains(name, "reptol")
            if settings["tolerance"] == "high"
                push!(traits,Trait(name, 0.75))
            elseif settings["tolerance"] == "low"
                push!(traits,Trait(name, 0.9)) #CAVE: code values elsewhere?
            elseif settings["tolerance"] == "none"
                push!(traits,Trait(name, 0.01)) #CAVE: code values elsewhere?
            else
                push!(traits,Trait(name, 0.5 + rand() * 0.5))
            end
        else
            push!(traits,Trait(name,rand()))
        end
    end
    traits
end

function creategenes(ngenes::Int64,traits::Array{Trait,1})
    genes = Gene[]
    for i in 1:ngenes
        sequence = String(rand(collect("acgt"), genelength)) # arbitrary start sequence
        codesfor = Trait[]
        push!(genes,Gene(sequence, codesfor))
    end
    for trait in traits
        ncodinggenes = rand(Poisson(1))
        while ncodinggenes < 1  # make sure every trait is coded by at least 1 gene
            ncodinggenes = rand(Poisson(1))
        end
        codinggenes = rand(genes,ncodinggenes)
        for gene in codinggenes
            push!(gene.codes,trait)
        end
    end
    if !any(map(x -> length(x.codes) == 0, genes)) # make sure there is a neutral gene!
        push!(genes, Gene(String(rand(collect("acgt"), genelength)), Trait[]))
    end
    push!(genes, Gene(String(rand(collect("acgt"), genelength)), [Trait("compat", 1.0)])) # create extra compatibility gene
    genes
end

function createchrs(nchrs::Int64,genes::Array{Gene,1})
    ngenes=size(genes,1)
    if nchrs>1
        chrsplits = sort(rand(1:ngenes,nchrs-1))
        chromosomes = Chromosome[]
        for chr in 1:nchrs
            if chr==1 # first chromosome
                push!(chromosomes, Chromosome(genes[1:chrsplits[chr]], true))
            elseif chr==nchrs # last chromosome
                push!(chromosomes, Chromosome(genes[(chrsplits[chr-1]+1):end], true))
            else
                push!(chromosomes, Chromosome(genes[(chrsplits[chr-1]+1):chrsplits[chr]], true))
            end
        end
    else # only one chromosome
        chromosomes = [Chromosome(genes, true)]
    end
    secondset = deepcopy(chromosomes)
    for chrm in secondset
        chrm.maternal = !chrm.maternal
    end
    append!(chromosomes,secondset)
    chromosomes
end
