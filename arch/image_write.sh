show_help() {
	echo "  --device, USB device, like /dev/sda"
	echo "  -h, --help  Show this info"
	exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
	    -d|--device)
		    if [[ -n "$2" && "$2" != -* ]]; then
			    DEVICE="$2"
			    shift 2 #shift by flag and its value 
		    else
			    echo "Error: Flag $1 requires value" >&2
			    exit 1
		    fi
		    ;;
	    -v|--verbose)
		    DEFAULT=0
		    if [[ -n "$2" && "$2" != -* ]]; then
			    VERBOSE="$2"
			    shift 2
		    else
			    VERBOSE=DEFAULT
		    fi
		    ;;
	    -h|--help)
		    show_help
		    ;;
	    -*)
		    echo "Error: Unknown flag $1" >&2
		    exit 1
		    ;;
	    *)
		    #positional args handling
		    POSITIONAL_ARGS+=("$1")
		    shift
		    ;;
    esac
done


set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

sudo umount "$DEVICE"*
sudo dd if="$(pwd)"/dev/archlinux.iso of="$DEVICE" bs=4M conv=fsync status=progress
sync
sleep 3
sudo udisksctl power-off -b "$DEVICE"
