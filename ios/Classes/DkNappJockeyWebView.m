/**
 * Module developed by Napp ApS
 * www.napp.dk
 * Mads Møller
 *
 * Appcelerator Titanium is Copyright (c) 2009-2010 by Appcelerator, Inc.
 * and licensed under the Apache Public License (version 2)
 */

#import "DkNappJockeyWebView.h"

@implementation DkNappJockeyWebView
@synthesize reloadData, reloadDataProperties, url, catchAllHTTPRequests;

-(void)dealloc
{
    if (webview!=nil)
    {
        webview.delegate = nil;
        
        // per doc, must stop webview load before releasing
        if (webview.loading)
        {
            [webview stopLoading];
        }
    }
    RELEASE_TO_NIL(webview);
    RELEASE_TO_NIL(url);
    RELEASE_TO_NIL(reloadData);
    RELEASE_TO_NIL(reloadDataProperties);
    RELEASE_TO_NIL(lastValidLoad);
    [super dealloc];
}

-(UIWebView*)webview
{
	if (webview==nil)
	{
		// we attach the XHR bridge the first time we need a webview
		webview = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
		webview.delegate = self;
		webview.opaque = NO;
		webview.backgroundColor = [UIColor whiteColor];
		webview.contentMode = UIViewContentModeRedraw;
		webview.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
		[self addSubview:webview];
	}
    
	return webview;
}

-(void)render
{
    ENSURE_UI_THREAD_0_ARGS;
    [self webview];
}

- (id)accessibilityElement
{
	return [self webview];
}


-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
    [super frameSizeChanged:frame bounds:bounds];
	
	if (webview!=nil)
	{
		[TiUtils setView:webview positionRect:bounds];
	}
}

- (void)setUrl_:(id)args
{
    ignoreNextRequest = YES;
    [self setReloadData:args];
    [self setReloadDataProperties:nil];
    reloadMethod = @selector(setUrl_:);
    
    RELEASE_TO_NIL(url);
    RELEASE_TO_NIL(lastValidLoad);
    ENSURE_SINGLE_ARG(args,NSString);
    
	url = [[TiUtils toURL:args proxy:(TiProxy*)self.proxy] retain];
    
    if(debug){
        NSLog(@"[NappJockey] setting url: %@", [url absoluteString]);
    }
    
	// load
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [webview loadRequest:request];
}

- (void)setDebug_:(id)args
{
	debug = [TiUtils boolValue:args];
}

- (void)reload
{
    RELEASE_TO_NIL(lastValidLoad);
    if (webview == nil)
    {
        return;
    }
    if (reloadData != nil)
    {
        [self performSelector:reloadMethod withObject:reloadData withObject:reloadDataProperties];
        return;
    }
    [webview reload];
}

- (void)stopLoading
{
	[webview stopLoading];
}

- (void)goBack
{
	[webview goBack];
}

- (void)goForward
{
	[webview goForward];
}

-(BOOL)isLoading
{
	return [webview isLoading];
}

-(BOOL)canGoBack
{
	return [webview canGoBack];
}

-(BOOL)canGoForward
{
	return [webview canGoForward];
}


- (void)sendJockeyData:(id)args
{
    if(debug){
        NSLog(@"[NappJockey] sending Data Event: %@", [args objectAtIndex:0]);
    }
    NSDictionary *payload = @{@"data": [args objectAtIndex:1]};
    [Jockey send:[TiUtils stringValue:[args objectAtIndex:0]] withPayload:[args objectAtIndex:1] toWebView:[self webview]];
}


#pragma mark WebView Delegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if(debug){
        NSLog(@"[NappJockey] shouldStartLoadWithRequest url: %@", [[request URL] absoluteString]);
    } 
    
    NSURL *newUrl = [request URL];
    
	if ([self.proxy _hasListeners:@"beforeload"] && newUrl != nil)
	{
		NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:[newUrl absoluteString], @"url", NUMINT(navigationType), @"navigationType", nil];
		[self.proxy fireEvent:@"beforeload" withObject:event];
	}
    
	if (navigationType != UIWebViewNavigationTypeOther) {
		RELEASE_TO_NIL(lastValidLoad);
	}
    
    // USING JOCKEY
    if ( [[[request URL] scheme] isEqualToString:@"jockey"] )
    {
        NSString *query = [[request URL] query];
        NSString *jsonString = [query stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        NSError *error;
        NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData: [jsonString dataUsingEncoding:NSUTF8StringEncoding]
                                                             options: NSJSONReadingMutableContainers
                                                               error: &error];
        
        NSString *eventName = [JSON objectForKey:@"type"];
        
        // send event
        if ([self.proxy _hasListeners:eventName]) {
            if(debug){
                NSLog(@"[NappJockey] Receiving Event name: %@", eventName);
            }
            
            NSDictionary *event = @{ @"payload": [JSON objectForKey:@"payload"] };
            [self.proxy fireEvent:eventName withObject:event];
        } else {
            if(debug){
                NSLog(@"[NappJockey] [ERROR] No Event Found for: %@", eventName);
            }
        }
        return NO;
    }
    
    NSString * scheme = [[newUrl scheme] lowercaseString];
    if ([scheme hasPrefix:@"http"] || [scheme isEqualToString:@"ftp"]
        || [scheme isEqualToString:@"file"] || [scheme isEqualToString:@"app"]) {
        DebugLog(@"[DEBUG] New scheme: %@",request);
        BOOL valid = !ignoreNextRequest;
        if ([scheme hasPrefix:@"http"]) {
            //UIWebViewNavigationTypeOther means we are either in a META redirect
            //or it is a js request from within the page
            if (catchAllHTTPRequests) return NO;
            valid = valid && (navigationType != UIWebViewNavigationTypeOther);
        }
        if (valid) {
            [self setReloadData:[newUrl absoluteString]];
            [self setReloadDataProperties:nil];
            reloadMethod = @selector(setUrl_:);
        }
        return YES;
    }
    
    if(debug){
        NSLog(@"[NappJockey] No jockey event - fallback");
    }
    
	//return [Jockey webView:[self webview] withUrl:[request URL]];
    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    // Wait until the UIWebView object has fully loaded.
    if (webview.isLoading){
        return;
    }
    
    [url release];
    url = [[[webview request] URL] retain];
    
    if(debug){
        NSLog(@"[NappJockey] webViewDidFinishLoad url: %@", [url absoluteString]);
    }
    
    NSString* urlAbs = [url absoluteString];
    [[self proxy] replaceValue:urlAbs forKey:@"url" notification:NO];
    
    if ([self.proxy _hasListeners:@"load"]) {
        if (![urlAbs isEqualToString:lastValidLoad] && url != nil) {
            NSDictionary *event = [NSDictionary dictionaryWithObject:urlAbs forKey:@"url"];
            [self.proxy fireEvent:@"load" withObject:event];
            [lastValidLoad release];
            lastValidLoad = [urlAbs retain];
        }
    }
    
    ignoreNextRequest = NO;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSString *offendingUrl = [self url];
    
    if ([[error domain] isEqual:NSURLErrorDomain])
    {
        offendingUrl = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
        
        // this means the pending request has been cancelled and should be
        // safely squashed
        if ([error code]==NSURLErrorCancelled)
        {
            return;
        }
    }
    
    NSLog(@"[ERROR] Error loading: %@, Error: %@",offendingUrl,error);
    
    if ([self.proxy _hasListeners:@"error"])
    {
        NSString * message = [TiUtils messageFromError:error];
        NSMutableDictionary *event = [NSMutableDictionary dictionaryWithObject:message forKey:@"message"];
        
        // We combine some error codes into a single one which we share with Android.
        NSInteger rawErrorCode = [error code];
        NSInteger returnErrorCode = rawErrorCode;
        
        if (rawErrorCode == NSURLErrorUserCancelledAuthentication)
        {
            returnErrorCode = NSURLErrorUserAuthenticationRequired; // URL_ERROR_AUTHENTICATION
        }
        else if (rawErrorCode == NSURLErrorNoPermissionsToReadFile || rawErrorCode == NSURLErrorCannotCreateFile || rawErrorCode == NSURLErrorFileIsDirectory || rawErrorCode == NSURLErrorCannotCloseFile || rawErrorCode == NSURLErrorCannotWriteToFile || rawErrorCode == NSURLErrorCannotRemoveFile || rawErrorCode == NSURLErrorCannotMoveFile)
        {
            returnErrorCode = NSURLErrorCannotOpenFile; // URL_ERROR_FILE
        }
        else if (rawErrorCode == NSURLErrorDNSLookupFailed)
        {
            returnErrorCode = NSURLErrorCannotFindHost; // URL_ERROR_HOST_LOOKUP
        }
        
        [event setObject:[NSNumber numberWithInteger:returnErrorCode] forKey:@"errorCode"];
        [event setObject:offendingUrl forKey:@"url"];
        [self.proxy fireEvent:@"error" withObject:event];
        //[self.proxy fireEvent:@"error" withObject:event errorCode:returnErrorCode message:message];
    }
}

@end
