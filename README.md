Termtris.jl
===========

A falling block game written in [Julia](http://julialang.org), that runs in your terminal window!

![Screen shot](sshot.png)

Controlled with arrows (left, right, up is rotate, down is drop).


## Install and run

`Termtris.jl` requires [TermWin.jl](https://github.com/tonyhffong/TermWin.jl) to be installed. Only tested on OSX in iTerm2, no guarantees anything works anywhere else.

```julia
julia> Pkg.add("TermWin")
julia> Pkg.clone("https://github.com/IainNZ/Termtris.jl.git")
```

Then to run either `julia> using Termtris` or at the command line `julia -e 'using Termtris'`

## Credits

* Based on [Lua Termtris](https://github.com/tylerneylon/termtris) by [Tyler Neylon](https://github.com/tylerneylon).

* `Termtris.jl` by [Iain Dunning](https://github.com/IainNZ).

* License not yet clarified.
