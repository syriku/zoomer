.PHONY: build test native app windows run clean

build:
	dotnet build Zoomer.slnx

test:
	dotnet run --project tests/Zoomer.Core.Tests/Zoomer.Core.Tests.csproj

native:
	./scripts/build-native.sh

app:
	./scripts/build-app.sh

windows:
	dotnet publish src/Zoomer.App/Zoomer.App.csproj -c Release -f net10.0-windows10.0.19041.0 -r win-x64 --self-contained false -p:PublishSingleFile=true -p:PublishAot=false -p:PublishTrimmed=false -p:DebugType=None -o artifacts/windows/win-x64/Release

run: app
	open artifacts/app/Zoomer.app

clean:
	dotnet clean Zoomer.slnx
	rm -rf artifacts
