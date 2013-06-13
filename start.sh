
if [ -d /var/lib/gems/1.9.1/bin ]; then
	PATH=$PATH:/var/lib/gems/1.9.1/bin
fi

mkdir -p cinchize
exec cinchize --start mensearch
