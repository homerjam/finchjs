isObject = (object) -> ( typeof object == typeof {} );
isFunction = (object) -> Object::toString.call( object ) is "[object Function]"
isArray = (object) -> Object::toString.call( object ) is "[object Array]"
isString = (object) -> Object::toString.call( object ) is "[object String]"

trim = (str) -> str.replace(/^\s\s*/, '').replace(/\s\s*$/, '')
startsWith = (haystack, needle) -> haystack.indexOf(needle) is 0
endsWith = (haystack, needle) ->  haystack.indexOf(needle, haystack.length - needle.length) isnt -1

extend = (obj, extender) ->
	obj = {} unless isObject(obj)
	extender = {} unless isObject(extender)

	obj[key] = value for key, value of extender
		
	return obj

#
assignedPatterns = {}

###
# Method used to standardize a route so we can better parse through it
###
standardizeRoute = (route) ->

	#Get a valid rotue
	route = if isString(route) then trim(route) else ""

	#Check for a leading bracket
	if startsWith(route, "[")

		#Find the index of the closing bracket
		closingBracketIndex = route.indexOf("]")

		# if the closing bracket is in a spot where it would have other chacters (a parent route)
		# remove the bracket and pin the two route pieces together
		if closingBracketIndex > 1
			route = route.slice(1, closingBracketIndex) + route.slice(closingBracketIndex+1)
		
		#Otherwise just strip of anything before (including) the closing bracket
		else
			route = route.slice( Math.max(1, closingBracketIndex+1) )

	#Remove any leading or trailing '/'
	route = route.slice(1) if startsWith(route, "/")
	route = route.slice(0, route.length-1) if endsWith(route, "/")

	return route

###
# Method: getParentPattern
# 	Used to extract the parent pattern out of a given pattern
#	- A parent pattern is specified within brackets, ex: [/home]/news
#		'/home' would be the parent pattern
#	- Useful for identifying and calling the parent pattern's callback
#
# Arguments:
#	pattern - The pattern to dig into and find a parent pattern, if one exisst
#
# Returns
#	string - The idenfitfied parent pattern
###
getParentPattern = (pattern) ->
	#Initialzie the parameters
	pattern = if isString(pattern) then trim(pattern) else ""
	parentPattern = null

	#Check if we're starting with a bracket if startsWith(pattern, "[")
	if startsWith(pattern, "[")

		#find the closing bracket
		closingBracketIndex = pattern.indexOf("]")

		#If we found one with a route inside, get the parentPattern
		if closingBracketIndex > 1
			parentPattern = pattern.slice(1, closingBracketIndex)
	
	return parentPattern

#END getParentPattern

###
# Method: getParameters
# 	Used to extract the parameters out of a route (from within the route's path, not query string)
#
# Arguments:
#	pattern - The pattern to use as a reference for finding parameters
#	route - The given route to extract parameters from
#
# Returns:
#	object - An object of the route's parameters
#
# See Also:
#	parseQuryString
###
getParameters = (pattern, route) ->
	route = "" unless isString(route)
	pattern = "" unless isString(pattern)

	route = standardizeRoute(route)
	pattern = standardizeRoute(pattern)

	routeSplit = route.split("/")
	patternSplit = pattern.split("/")

	return {} if routeSplit.length isnt patternSplit.length

	parameters = {}

	for index, patternPiece of patternSplit
		if startsWith(patternPiece, ":")
			parameters[patternPiece.slice(1)] = routeSplit[index] 

	return parameters

#END getParameters

###
# Method: parseQueryString
#	Used to parse and objectize a query string
#
# Arguments: 
#	queryString - The query string to split up into an object
#
# Returns:
#	object - An object of the split apart query string
###
parseQueryString = (queryString) ->

	#Make sure the query string is valid
	queryString = if isString(queryString) then trim(queryString) else ""

	#setup the return params
	queryParams = {}

	#iterate through the pieces of the query string
	for piece in queryString.split("&")
		[key, value] = piece.split("=", 2)
		queryParams[key] = value
	
	#return the result
	return queryParams

#END parseQueryString

###
# Method: matchPattern
#	Method used to determine if a route matches a pattern
#
# Arguments:
#	route - The route to check
#	pattern - The pattern to compare the route against
#
# Returns:
#	boolean - Did the route match the pattern?
###
matchPattern = (route, pattern) ->
	route = standardizeRoute(route)
	pattern = standardizeRoute(pattern)

	routeSplit = route.split("/")
	patternSplit = pattern.split("/")

	#if the lengths aren't the same, this isn't valid
	return false if routeSplit.length isnt patternSplit.length

	for index, patternPiece of patternSplit
		return false unless patternPiece is routeSplit[index] or startsWith(patternPiece, ":")

	return true

#END matchPattern

###
# Method: buildCallStack
#	Used to build up a callstack for a given patterrn
#
# Arguments:
#	pattern - The route pattern to try and call
###
buildCallStack = (pattern) ->

	pattern = standardizeRoute(pattern)
	callStack = []

	#Next build the callstack
	(stackAdd = (pattern) ->
		pattern = assignedPatterns[pattern]

		if isObject(pattern)
			callStack.push(pattern) if isFunction(pattern.setup)
			stackAdd(pattern.parentPattern) if pattern.parentPattern? and pattern.parentPattern isnt ""
	)(pattern)

	return callStack
#END buildCallStack

###
# Method: runCallStack
#	Used to execute a callstack from a route starting at it's top most parent
#
# Arguments:
#	stack - The stack to iterate through
#	parameters - The parameters to extend onto the list of parameters to send onward
###
runCallStack = (callStack, parameters) ->

	#First setup the variables
	callStack = [] unless isArray(callStack)
	parameters = {} unless isObject(parameters)

	#TODO: Eliminate steps in the call stack that have already been run, optimization

	#Lastly execute the callstack, taking into account methods that request for the child callback
	(callItem = (stack, parameters) ->
		return if stack.length <= 0

		item = stack.pop()
		item = {} unless isObject(item)
		setup = (->) unless isFunction(item.setup)

		if item.setup.length == 2
			item.setup( parameters, (p) -> 
				p = {} unless isObject(p)
				extend(parameters, p)
				callItem.call( callItem, stack, parameters )
			)
		else
			item.setup(parameters)
			callItem(stack, parameters)
	)(callStack, parameters)

	return

#END runCallStack

###
# Method: extrapolateRouteStack
#	Used to extrpolate a stack of routes that will
#	be called with the given route (full routes, not patterns)
#
# Arguments:
#	pattern - The pattern to reference
#	route - The route to extrpolate from
###
extrapolateRouteStack = (pattern, route) ->
	#Setup the parameters
	pattern = standardizeRoute(pattern)
	route = standardizeRoute(route)
	routeSplit = route.split("/")
	routeStack = []

	return routeStack if routeSplit.length <= 0

	(extrapolate = (pattern) ->

		#split up the pattern
		patternSplit = pattern.split("/")
		extrapolatedRoute = ""
		matches = true
		splitIndex = 0


		#Iterate over the pieces to build the extrpolated route
		while matches and patternSplit.length > splitIndex and routeSplit.length > splitIndex

			#Get the two pieces
			patternPiece = patternSplit[splitIndex]
			routePiece = routeSplit[splitIndex]

			#Should we add the route to the extrpolated route
			if startsWith(patternPiece, ":") or patternPiece is routePiece
				extrapolatedRoute += "#{routePiece}/"
			else
				matches = false

			#Increment the counter
			splitIndex++
		#END while
		
		#Remove the last '/'
		extrapolatedRoute = extrapolatedRoute.slice(0,-1) if endsWith(extrapolatedRoute, "/")
		
		#Get the assigned pattern
		assignedPattern = assignedPatterns[pattern]

		#call to extrpolate the parent route, if we extrpolated something in he child route
		if extrapolatedRoute isnt ""
			routeStack.push(extrapolatedRoute)
			extrapolate(assignedPattern.parentPattern, route) if assignedPattern.parentPattern? and assignedPattern.parentPattern isnt ""

	)(pattern)

	return routeStack
#END extrapolateRouteStack



###
# Class: Finch
###
Finch = {

	###
	# Mathod: Finch.route
	#	Used to setup a new route
	#
	# Arguments:
	#	pattern - The pattern to add
	#	callback - The callback to assign to the pattern
	###
	route: (pattern, callback) ->

		#Make sure we have valid inputs
		pattern = "" unless isString(pattern)
		callback = (->) unless isFunction(callback)

		#initialize the parent route to call
		parentPattern = getParentPattern(pattern)

		#Standardize the rotues
		pattern = standardizeRoute(pattern)
		parentPattern = standardizeRoute(parentPattern)

		#Store the action for later
		assignedPatterns[pattern] = {
			context: {}
			pattern: pattern
			parentPattern: parentPattern
			setup: callback
			teardown: (->)
		}
		
		#END assignedPatterns[route]
	
	#END Finch.route

	###
	# Method: Finch.call
	#
	# Arguments:
	#	route - The route to try and call
	#	parameters (optional) - The initial prameters to send
	###
	call: (uri, parameters) ->


		#Make sure we have valid arguments
		uri = "" unless isString(uri)
		parameters = {} unless isObject(parameters)

		#Extract the route and query string from the uri
		[route, queryString] = uri.split("?", 2)
		route = standardizeRoute(route)
		queryParams = parseQueryString(queryString)

		#Extend the parameters with those found in the query string
		extend(parameters, queryParams)

		# Check if the user is just trying to call on a pattern
		# If so just call it's callback and return
		return assignedPatterns[route](parameters) if isFunction(assignedPatterns[route])

		# Iterate over each of the assigned routes and try to find a match
		for pattern, config of assignedPatterns
			
			#Check if this route matches the input routpatterne
			if matchPattern(route, pattern)

				#Get the parameters of the route
				extend(parameters, getParameters(pattern, route))

				#Create a callstack for this pattern
				callStack = buildCallStack(pattern)

				#Execute the callstack
				runCallStack(callStack, parameters)

				#return true
				return true
			
			#END if match
		
		#END for pattern in assignedPatterns
		
		#return false, we coudln't find a route
		return false
	
	#END Finch.call()
}

#Expose Finch to the window
@Finch = Finch