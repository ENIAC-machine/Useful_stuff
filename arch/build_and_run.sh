show_help() {
	echo "  --device, USB device, like /dev/sda"
	echo "  -h, --help Show this"
	echo "If you haven't read the README.md then pls do, it's literally in the name"
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


sudo podman build -t archiso_script . &&\
	sudo podman run --privileged --mount type=bind,source="$(pwd)"/dev,target=/home/dev -it localhost/archiso_script &&\
	bash image_write.sh --device "$DEVICE"
