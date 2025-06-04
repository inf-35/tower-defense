class_name EventData
#see child classes i.e. hit_data, etc.
var recursion: int = 0 #counter to prevent infinite recursion loops, stops at recursion_limit (see Effect.RECURSION_LIMIT)
