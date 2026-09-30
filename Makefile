.PHONY: app run install clean

app:
	./scripts/build-app.sh

run: app
	open Zone.app

install: app
	rm -rf /Applications/Zone.app
	cp -R Zone.app /Applications/

clean:
	rm -rf .build Zone.app
