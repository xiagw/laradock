@echo off

curl.exe -LO https://cdn.flyh6.com/docker/xampp.zip

powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive .\xampp.zip C:\xampp\"
