-- swarm-update.lua
-- Fetches the latest version of swarm from github, then updates all swarm files.
swarmHost = "http://raw.githubusercontent.com/Cyrixus/swarm/master/"
swarmFiles = swarmHost .. "swarm-files.cfg"

if http then
    -- We can use HTTP, get the latest set of swarm files
    fileList = http.get(swarmFiles)
    if file == nil then
        error("Could not connect to swarmHost [" .. swarmFiles .. "]")
    else
        -- Got the file list successfully, so now read each file and save it to disk
        fileName = fileList.readLine()
        while fileName ~= nil do
            file = http.get(swarmHost .. fileName)
            
            outFile = fs.open(shell.resolve("") .. "/" .. fileName, "w")
            outFile.write(file.readAll())
            outFile.close()
        end
    end
    
else
    -- No HTTP access, we're DOA
    error("HTTP is not enabled, cannot fetch latest swarm.")
end
