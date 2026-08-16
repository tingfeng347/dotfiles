function __fastfetch_render
    set -l columns (tput cols 2>/dev/null)

    # The complete logo-and-details layout needs 106 columns; keep a small buffer.
    if test -n "$columns"; and test "$columns" -lt 112
        command fastfetch --logo none $argv
    else
        command fastfetch $argv
    end
end

function fastfetch --wraps fastfetch --description 'Run Fastfetch with a width-aware layout'
    set -g __fastfetch_redraw_args $argv
    set -g __fastfetch_redraw_pending 1
    __fastfetch_render $argv
end

function __fastfetch_redraw_on_resize --on-signal WINCH
    if not status is-interactive; or not set -q __fastfetch_redraw_pending
        return
    end

    clear
    __fastfetch_render $__fastfetch_redraw_args
    commandline -f repaint
end

function __fastfetch_stop_redraw --on-event fish_preexec
    set -e __fastfetch_redraw_pending
    set -e __fastfetch_redraw_args
end
