# inquisitarr
Blacklist script for Jellyseerr API

For blacklist family need for Jellyseerr.
Here's my script Inquisitarr.sh that contacts the Seer (previously Jellyseerr) API to blacklist all elements based on a keyword.
Watch out for the blacklisted results, as some of them are well-known movies.

No log file, only a short output.
Output example :
```Result: 12 added | 185 already listed | 0 failed | 197/197 processed```




# Last release updates

1. Added a movie limit prompt
2. Properly caps the requested amount
3. Much faster processing through parallel requests
4. Removed the sleep 1 delay between pages
5. Only fetches the number of pages actually needed
6. Reuses the first movie page instead of downloading it twice
7. Added safer shell behavior
8. Added stronger dependency checks
9. Added input validation
10. Proper URL encoding for keyword searches
11. Fixed handling of titles with quotes, apostrophes, and special characters
12. Switched to a safer movie transport format
13. Safer JSON payload generation
14. Correct duplicate detection using HTTP status codes
15. Added fallback text detection for Seerr/Overseerr wording differences
16. Fixed inaccurate result reporting
17. Parallel-safe counters
18. Automatic cleanup of temporary files
19. Reduced output verbosity
20. Removed unnecessary API response dumping
21. Cleaner error reporting
22. Better handling of “no results” cases
23. More accurate page-size handling
24. Summary is now compact and useful
