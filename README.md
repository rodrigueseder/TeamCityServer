# TemaCityServer

### Initial app with startup scripts
	- Script to create itself (azure, aws), it could be a lambda/funtion
	- If cloud, should call other apps creation. If on premise, should create the build/deployment app, that will then create the other pipelines
	- Each pipeline/app will have the code to build itself

### Build/Deployment server (Go, Team City)
	- Script to create itself
	- Script to call the other pipelines creation script

### Other servers (database, etc)
	- Script to create itself as pipeline (on premise)
	- Source Code
	
### Other apps
	- Script to create itself as app (on cloud)
	- Script to create itself as pipeline (on premise)
	- Source Code

### References
https://essenceofcode.com/2012/08/20/using-msbuild-and-team-city-for-deployments-part-1-introduction/
http://www.mono-project.com/docs/
https://confluence.jetbrains.com/display/TCD10/REST+API
https://msdn.microsoft.com/en-us/powershell/reference/5.1/microsoft.powershell.utility/convertfrom-json
