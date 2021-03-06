# Notes To Self
This is a temporary repository. Custom tweaks to docfx v2 were required for personal plugins to work.

## Dll Loading Issues
1. Run ildasm in the plugins directory to find out what version of the dll we actually end up with.
2. Look through obj/project.assets.json to figure out why hoisting is occuring, if possible, update dependencies so
references to the dll are all for the same versions.
3. If upgrading can't solve the issue (the newest version of some package references an older version of the dll), 
add a binding redirection to docfx.plugins.config. Ensure that docfx.plugins.config is copied to theme/plugins. 
4. Binding redirections may cause exceptions in the main assembly context if redirected-to-dlls aren't present in the 
docfx project's bin. If this is the case, add package references to the dll directly in docfx.csproj.

## Building
Run build.ps1 without arguments. Packages will be generated in docfx/artifacts/release. docfx.console.<version>/tools contains
the docfx.exe.

## Updating Version
Set build.ps1 > $packageVersion.

## CI
Pushing to origin/dev triggers a build that uploads generated packages to the Azure Artifacts feed for this project.

