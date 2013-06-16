
if [ -d /var/lib/gems/1.9.1/bin ]; then
	PATH=$PATH:/var/lib/gems/1.9.1/bin
fi

mkdir -p cinchize
case "$(readlink cinchize.yml)" in
  cinchize.yml.live)
    exec cinchize --start mensearch
    ;;
  cinchize.yml.test)
    exec cinchize --start mensearcht
    ;;
esac
