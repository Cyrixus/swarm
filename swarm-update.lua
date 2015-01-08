--[[ swarm-update.lua
    Fetches the latest version of swarm from github, then updates all swarm files.
]]--

-- Default host definitions
local swarmHost = "http://raw.githubusercontent.com/Cyrixus/swarm/master/"
local swarmFiles = swarmHost .. "swarm-files.cfg"

if http then
    print("Beginning update...")
    -- We can use HTTP, get the latest set of swarm files
    local fileList = http.get(swarmFiles)
    if fileList == nil then
        error("Could not connect to swarmHost [" .. swarmFiles .. "]")
    else
        -- Got the file list successfully, so now read each file and save it to disk
        print("File list retrieved, downloading swarm...")
        local fileName = fileList.readLine()
        while fileName ~= nil do
            -- Retrieve the file from swarmHost
            local file = http.get(swarmHost .. fileName)
            if file == nil then
                error("Could not fetch file [" .. fileName .. "]")
            end
            
            -- Write the file to disk
            local outFile = fs.open(shell.resolve("") .. "/" .. fileName, "w")
            outFile.write(file.readAll())
            outFile.close()
            print("Saved " .. fileName .. "...")

            -- Get the next file in the list
            fileName = fileList.readLine()
        end
        print("Done.")
    end
    
else
    -- No HTTP access, we're DOA
    error("HTTP is not enabled, cannot fetch latest swarm.")
end
