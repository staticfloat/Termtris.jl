#----------------------------------------------------------------------
# Termtris.jl
# A port of Tyler Neylon's termtris (Lua)
# Original: https://github.com/tylerneylon/termtris
#    Julia: https://github.com/IainNZ/Termtris.jl
#----------------------------------------------------------------------
# Notes on the port
# The author doesn't actually know Lua, but the translation was
# "obvious" that it didn't matter. A minimal amount of changes have
# been made. Most notable is the use in the Lua version of what would
# be Dicts in the Julia version (I believe they are "tables" in Lua).
# This is not even close to idiomatic Julia, and have been replaced
# with constants, symbols, and types where appropriate.

# Of course, the curses code is a bit different. Julia doesn't have
# a simple curses package yet, but TermWin.jl has most of what we need.
# Where it doesn't have the ideal function wrapped, I improvised with
# what I had (and a very imperfect understanding of ncurses!)
import TermWin
#const KEY_UP = cglobal(dlsym(TermWin.libncurses, :KEY_UP), Int16)

#----------------------------------------------------------------------
# Constants
const BOARD_SIZE_X = 11
const BOARD_SIZE_Y = 20
const BORDER_X = BOARD_SIZE_X + 1
const BORDER_Y = BOARD_SIZE_Y + 1

# The six basic shapes.
const BASE_SHAPES = {
    [0 1 0;
     1 1 1],
    [0 1 1;
     1 1 0],
    [1 1 0;
     0 1 1],
    [1 1 1 1],
    [1 1;
     1 1],
    [1 0 0;
     1 1 1],
    [0 0 1;
     1 1 1]
}

# Set up the shapes table with four 90 degree rotations of
# the base shapes
SHAPES = [i => {s,
                s'[:,end:-1:1],
                s[end:-1:1,end:-1:1],
                s'[end:-1:1,:]}
            for (i, s) in enumerate(BASE_SHAPES)]

#----------------------------------------------------------------------
# A Piece is an instance of a shape. It has a base shape, a rotation,
# and a location.
# NB: in the original Lua, this was a `table` (I think)
type Piece
    shape
    rot_num
    x
    y
end
Base.copy(p::Piece) = Piece(p.shape,p.rot_num,p.x,p.y)
# Calls fn(x,y,arg) for each 1 in the Piece
# Returns a vector of results of fn
# NB: in the original Lua, this was `call_fn_for_xy_in_piece`
function map_fn_arg(p::Piece, fn, arg)
    s = SHAPES[p.shape][p.rot_num]
    rows, cols = size(s)
    results = Any[]
    for y = 1:rows, x = 1:cols
        s[y,x] == 1 &&
            push!(results, fn(p.x + x, p.y + y, arg))
    end
    return results
end
# Draws the piece at a given offset
function draw_piece(p::Piece, x_offset)
    set_color(p.shape)
    map_fn_arg(p, draw_point, x_offset)
end
# Returns true if all parts of piece are in empty space
function check_piece_valid(p::Piece)
    check_valid(x,y,_) = (board[(x,y)] == :empty)
    all(map_fn_arg(p, check_valid, nothing))
end
# Lock a piece into the board representation
function lock_piece(p::Piece)
    global board
    locker(x,y,s) = (board[(x,y)] = s)
    map_fn_arg(p, locker, p.shape)
end

#----------------------------------------------------------------------
# Declare internal globals.


game_state = :playing  # could also be :paused or :over
stdscr = nothing  # This will be the standard screen
                  # from the curses library
board = Dict()  # board[(x,y)] = <piece at (x, y)>; 0 = empty, -1 = border.
# We'll write *shape* for an index into the shapes table; the
# term *piece* also includes a rotation number and x, y coords.
moving_piece = {}  # Keys will be: shape, rot_num, x, y.

#----------------------------------------------------------------------
# Set the colors given an color-pair number
set_color(c) = TermWin.wattron(stdscr,TermWin.COLOR_PAIR(c))

# Space is the default point_char.
function draw_point(x, y, x_offset, color=nothing, point_char=' ')
    color != nothing && set_color(color)
    # Don't draw pieces when the game is paused.
    if point_char == ' ' && game_state == :paused
        return
    end 
    TermWin.mvwaddch(stdscr, y, x_offset + 2 * x + 0, point_char)
    TermWin.mvwaddch(stdscr, y, x_offset + 2 * x + 1, point_char)
end

function init()
    # Use the current time as our random seed
    srand(time_ns())

    # Start up curses.
    global stdscr
    stdscr = TermWin.initscr()  # Initialize the curses library and the terminal screen.
    TermWin.cbreak()  # Turn off input line buffering.
    TermWin.noecho()  # Don't print out characters as the user types them.
    #curses.nl(false)  # Turn off special-case return/newline handling.
    TermWin.curs_set(0)  # Hide the cursor.

    # Set up colors.
    TermWin.start_color()
    if !TermWin.has_colors()
        TermWin.endwin()
        print("Bummer! Looks like your terminal doesn't support colors :'(")
        return
    end
    colors = [:white => 1, :blue => 2, :cyan => 3, :green => 4,
              :magenta => 5, :red => 6, :yellow => 7, :black => 8]
    TermWin.init_pair(1, TermWin.COLOR_WHITE,   TermWin.COLOR_WHITE)
    TermWin.init_pair(2, TermWin.COLOR_BLUE,    TermWin.COLOR_BLUE)
    TermWin.init_pair(3, TermWin.COLOR_CYAN,    TermWin.COLOR_CYAN)
    TermWin.init_pair(4, TermWin.COLOR_GREEN,   TermWin.COLOR_GREEN)
    TermWin.init_pair(5, TermWin.COLOR_MAGENTA, TermWin.COLOR_MAGENTA)
    TermWin.init_pair(6, TermWin.COLOR_RED,     TermWin.COLOR_RED)
    TermWin.init_pair(7, TermWin.COLOR_YELLOW,  TermWin.COLOR_YELLOW)
    TermWin.init_pair(8, TermWin.COLOR_BLACK,   TermWin.COLOR_BLACK)
    colors[:text] = 9
    colors[:over] = 10
    TermWin.init_pair( 9, TermWin.COLOR_WHITE, TermWin.COLOR_BLACK)
    TermWin.init_pair(10, TermWin.COLOR_RED,   TermWin.COLOR_BLACK)

    # Set up our standard screen.
    TermWin.nodelay(stdscr, true)  # Make getch nonblocking.
    TermWin.keypad(stdscr, true)  # Correctly catch arrow key presses.

    # Set up the board.
    global board
    for x = 0:BORDER_X
        for y = 1:BORDER_Y
            board[(x,y)] = :empty
            if x == 0 || x == BORDER_X || y == BORDER_Y
                board[(x,y)] = :border  # This is a border cell.
            end
        end
    end

    # Set up the next and currently moving piece.
    global moving_piece
    moving_piece = Piece(rand(1:length(BASE_SHAPES)),1,4,0)
    next_piece   = Piece(rand(1:length(BASE_SHAPES)),1,0,0)

    stats = [:level => 1, :lines => 0, :score => 0]

    # fall.interval is the number of seconds between downward piece movements.
    fall = [:interval => 0.5, :last_at => time_ns() / 10^9]

    return stats, fall, colors, next_piece
end


function draw_screen(stats, colors, next_piece)
    TermWin.erase()

    # Update the screen dimensions.
    scr_width = Base.tty_size()[2]
    win_width = 2 * (BOARD_SIZE_X + 2) + 16
    x_margin  = div(scr_width - win_width, 2)
    x_labels  = x_margin + win_width - 10

    # Draw the board's border and non-falling pieces
    # if we're not paused.
    color_of_val = [:border => game_state == :over ? 
                                    colors[:over] : colors[:text],
                    :empty  => colors[:black]]
    for x = 0:BOARD_SIZE_X+1
        for y = 1:BOARD_SIZE_Y+1
            # Draw ' ' for shape & empty points; '|' for border points.
            board_val = board[(x,y)]
            pt_char  = board_val == :border ? '|' : ' '
            pt_color = get(color_of_val, board_val, board_val)
            draw_point(x, y, x_margin, pt_color, pt_char)
        end
    end

    # Write 'paused' if the we're paused...
    if game_state == :paused then
        set_color(colors[:text])
        x = x_margin + BOARD_SIZE_X - 1  # Slightly left of center.
        TermWin.mvwprintw(stdscr, div(BOARD_SIZE_Y, 2), x, "%s", "paused")
    else
        # ... Draw the moving piece otherwise.
        draw_piece(moving_piece, x_margin)
    end

    # Draw the stats: level, lines, and score.
    set_color(colors[:text])
    TermWin.mvwprintw(stdscr,  9, x_labels, "%s", "Level $(stats[:level])")
    TermWin.mvwprintw(stdscr, 11, x_labels, "%s", "Lines $(stats[:lines])")
    TermWin.mvwprintw(stdscr, 13, x_labels, "%s", "Score $(stats[:score])")
    if game_state == :over then
        TermWin.mvwprintw(stdscr, 16, x_labels, "%s", "Game Over")
    end

    # Draw the next piece.
    TermWin.mvwprintw(stdscr, 2, x_labels, "%s", "----------")
    TermWin.mvwprintw(stdscr, 7, x_labels, "%s", "---Next---")
    fake_piece = Piece(next_piece.shape, 1, BOARD_SIZE_X+5, 3)
    draw_piece(fake_piece, x_margin)

    # Update the screen
    TermWin.refresh()
end

function lock_and_update_moving_piece(stats, fall, next_piece)
    global moving_piece

    # Lock the moving piece in place.
    lock_piece(moving_piece)

    # Clear any lines possibly filled up by the just-placed piece.
    num_removed = 0
    max_line_y = min(moving_piece.y + 4, BOARD_SIZE_Y)
    for line_y = moving_piece.y+1:max_line_y
        is_full_line = true
        for x = 1:BOARD_SIZE_X
            if board[(x,line_y)] == :empty
                is_full_line = false
            end
        end
        if is_full_line
            # Remove the line at line_y.
            for y = line_y:-1:2
                for x = 1:BOARD_SIZE_X
                    board[(x,y)] = board[(x,y-1)]
                end
            end
            # Record the line and level updates.
            stats[:lines] += 1
            if stats[:lines] % 10 == 0  # Level up when lines is a multiple of 10.
                stats[:level] += 1 
                fall[:interval] *= 0.8  # The pieces will fall faster.
            end
            num_removed = num_removed + 1
        end
    end
    #num_removed > 0 && TermWin.flash()
    stats[:score] += num_removed^2
    
    # Bring in the waiting next piece and set up a new next piece.
    moving_piece = Piece(next_piece.shape,1,4,0)
    if !check_piece_valid(moving_piece)
        global game_state
        game_state = :over
    end
    next_piece.shape = rand(1:length(BASE_SHAPES))
end


function handle_input(stats, fall, next_piece)
    global game_state

    key = TermWin.wgetch(stdscr)  # Nonblocking
    key == typemax(Uint32) && return true

    # The q key quits
    key == 'q' && return false

    # The p key pauses or unpauses
    if key == 'p'    
        game_state = (game_state == :paused) ? :playing :
                                               :paused
    end

    # Arrow keys only work if playing
    game_state != :playing && return true

    # Handle the left, right, or up arrows
    arrow = TermWin.ncnummap[key]
    # TODO: use constants from curses
    if arrow == :left
        piece_nextpos = copy(moving_piece)
        piece_nextpos.x -= 1
        if check_piece_valid(piece_nextpos)
            moving_piece.x -= 1
        end
    elseif arrow == :right
        piece_nextpos = copy(moving_piece)
        piece_nextpos.x += 1
        if check_piece_valid(piece_nextpos)
            moving_piece.x += 1
        end
    elseif arrow == :up  # Rotate
        piece_nextpos = copy(moving_piece)
        new_rot_num = (moving_piece.rot_num % 4) + 1
        piece_nextpos.rot_num = new_rot_num
        if check_piece_valid(piece_nextpos)
            moving_piece.rot_num = new_rot_num
        end
    elseif arrow == :down  # Drop to bottom
        piece_nextpos = copy(moving_piece)
        offset_y = 1
        while true
            piece_nextpos.y = moving_piece.y + offset_y
            !check_piece_valid(piece_nextpos) && break
            offset_y += 1
        end
        moving_piece.y += offset_y - 1
        lock_and_update_moving_piece(stats, fall, next_piece)
    end

    return true
end


function lower_piece_at_right_time(stats, fall, next_piece)
    # This function does nothing if the game is paused or over.
    game_state != :playing && return

    timestamp = time_ns() / 10^9  # seconds

    # Do nothing until it's been fall[:interval] seconds since the last fall.
    if timestamp - fall[:last_at] < fall[:interval]
        return
    end

    piece_nextpos = copy(moving_piece)
    piece_nextpos.y += 1
    if check_piece_valid(piece_nextpos)
        moving_piece.y += 1
    else
        lock_and_update_moving_piece(stats, fall, next_piece)
    end

    fall[:last_at] = timestamp
end

function main()
    stats, fall, colors, next_piece = init()

    while true  # Main loop
        # Quit if handle_input returns false
        if !handle_input(stats, fall, next_piece)
            break
        end
        lower_piece_at_right_time(stats, fall, next_piece)
        draw_screen(stats, colors, next_piece)
    
        # Don't poll for input much faster than the display changes
        sleep(0.005)  # seconds
    end

    # Clean up
    TermWin.endwin()
end

# Because crashing the ncurses active seems to make a mess of the
# terminal, we'll wrap the whole game in a try-catch to try to
# make it terminate cleanly
try
    main()
catch
    TermWin.endwin()
end
