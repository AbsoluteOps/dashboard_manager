- Create a folder to execute the scripts from (i.e. c:\dashboard)
  - Make sure the account you want to test has read and write privileges to this folder
- Extract the CSC Windows Agent files to the new folder
- Open Powershell
- Navigate to the folder that was created
- Run the follow command
`powershell -ep Bypass .\install.ps1 -apiKey <api_key>`
- Verify the scheduled task was created and runs after 5 minutes have passed