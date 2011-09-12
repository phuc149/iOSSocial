//
//  LocalFlickrUser.m
//  iOSSocial
//
//  Created by Christopher White on 7/22/11.
//  Copyright 2011 Mad Races, Inc. All rights reserved.
//

#import "LocalFlickrUser.h"
#import "Flickr.h"
#import "FlickrUser+Private.h"
#import "iOSSRequest.h"
#import "GTMOAuthAuthentication+Additions.h"
#import "iOSSLog.h"

NSString *const iOSSDefaultsKeyFlickrUserDictionary    = @"ioss_FlickrUserDictionary";

static LocalFlickrUser *localFlickrUser = nil;

@interface LocalFlickrUser () 

@property(nonatomic, copy)      FlickrAuthenticationHandler authenticationHandler;
@property(nonatomic, retain)    GTMOAuthAuthenticationWithAdditions *auth;
@property(nonatomic, retain)    NSString *keychainItemName;
@property(nonatomic, retain)    NSString *uuidString;

@end

@implementation LocalFlickrUser

@synthesize authenticated;
@synthesize authenticationHandler;
@synthesize username;
@synthesize servicename;
@synthesize auth;
@synthesize keychainItemName;
@synthesize uuidString;

+ (LocalFlickrUser *)localFlickrUser
{
    @synchronized(self) {
        if(localFlickrUser == nil)
            localFlickrUser = [[super allocWithZone:NULL] init];
    }
    return localFlickrUser;
}

+ (id<iOSSocialLocalUserProtocol>)localUser
{
    @synchronized(self) {
        if(localFlickrUser == nil)
            localFlickrUser = [[super allocWithZone:NULL] init];
    }
    return localFlickrUser;
}

- (NSDictionary *)ioss_FlickrUserDictionary 
{ 
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@", iOSSDefaultsKeyFlickrUserDictionary, self.uuidString]];
}

- (void)ioss_setFlickrUserDictionary:(NSDictionary *)theUserDictionary 
{ 
    [[NSUserDefaults standardUserDefaults] setObject:theUserDictionary forKey:[NSString stringWithFormat:@"%@-%@", iOSSDefaultsKeyFlickrUserDictionary, self.uuidString]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (id)init
{
    self = [super init];
    if (self) {
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        CFStringRef uuidStr = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        self.uuidString = (__bridge NSString *)uuidStr;
        CFRelease(uuidStr);
        CFRelease(uuid); 
        
        self.keychainItemName = [NSString stringWithFormat:@"InstaBeta_Flickr_Service-%@", self.uuidString];
        self.auth = [[Flickr sharedService] checkAuthenticationForKeychainItemName:self.keychainItemName];
        
        // Initialization code here.
        NSDictionary *localUserDictionary = [self ioss_FlickrUserDictionary];
        if (localUserDictionary) {
            self.userDictionary = localUserDictionary;
        }
    }
    
    return self;
}

- (id)initWithUUID:(NSString*)uuid
{
    self = [super init];
    if (self) {
        self.uuidString = uuid;
        
        self.keychainItemName = [NSString stringWithFormat:@"InstaBeta_Flickr_Service-%@", self.uuidString];
        self.auth = [[Flickr sharedService] checkAuthenticationForKeychainItemName:self.keychainItemName];
        
        // Initialization code here.
        NSDictionary *localUserDictionary = [self ioss_FlickrUserDictionary];
        if (localUserDictionary) {
            self.userDictionary = localUserDictionary;
        }
    }
    
    return self;
}

- (void)setUserDictionary:(NSDictionary *)theUserDictionary
{
    if (theUserDictionary) {
        [super setUserDictionary:theUserDictionary];
        
        [self ioss_setFlickrUserDictionary:theUserDictionary];
    } else {
        iOSSLog(@"meh: no user dictionary");
    }
}

- (BOOL)isAuthenticated
{
    if (NO == self.auth.canAuthorize)
        return NO;
    return YES;
}

- (NSURL*)authorizedURL:(NSURL*)theURL
{
    NSString *access_token = [NSString stringWithFormat:@"?auth_token=%@", [self oAuthAccessToken]];
    NSURL *url = [NSURL URLWithString:access_token relativeToURL:theURL];
    
    return url;
}

- (NSString*)apiEndpoint
{
    return @"http://api.flickr.com/services/rest/";
}

- (void)fetchLocalUserDataWithCompletionHandler:(FetchUserDataHandler)completionHandler
{
    self.fetchUserDataHandler = completionHandler;

    NSString *urlString = [NSString stringWithFormat:@"http://api.flickr.com/services/rest/?method=flickr.people.getInfo&user_id=%@&format=json&nojsoncallback=1", self.userID];
    
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    NSString *oauthRequestHeader = [[Flickr sharedService] authorizationHeaderForRequest:urlRequest withAuth:self.auth];
    
    NSURL *url = [NSURL URLWithString:urlString];

    iOSSRequest *request = [[iOSSRequest alloc] initWithURL:url  
                                                 parameters:nil 
                                              requestMethod:iOSSRequestMethodGET];
    [request requiresOAuth1AuthenticationWithParams:oauthRequestHeader];
    
    [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
        if (error) {
            if (self.fetchUserDataHandler) {
                self.fetchUserDataHandler(error);
                self.fetchUserDataHandler = nil;
            }
        } else {
            NSDictionary *dictionary = [Flickr JSONFromData:responseData];
            self.userDictionary = dictionary;
            
            if (self.fetchUserDataHandler) {
                self.fetchUserDataHandler(nil);
                self.fetchUserDataHandler = nil;
            }
        }
    }];
}

- (void)authenticateFromViewController:(UIViewController*)vc 
                 withCompletionHandler:(AuthenticationHandler)completionHandler;
{
    self.authenticationHandler = completionHandler;
    
    //cwnote: also see if permissions have changed!!!
    if (NO == [self isAuthenticated]) {

        [[Flickr sharedService] authorizeFromViewController:vc 
                                                     forAuth:self.auth 
                                         andKeychainItemName:self.keychainItemName 
                                             andCookieDomain:@"flickr.com" 
                                       withCompletionHandler:^(GTMOAuthAuthentication *theAuth, NSDictionary *userInfo, NSError *error) {
            self.auth = (GTMOAuthAuthenticationWithAdditions*)theAuth;
            if (error) {
                if (self.authenticationHandler) {
                    self.authenticationHandler(error);
                    self.authenticationHandler = nil;
                }
            } else {
                if (userInfo) {
                    NSDictionary *user = [userInfo objectForKey:@"user"];
                    self.userDictionary = user;
                }
                
                [self fetchLocalUserDataWithCompletionHandler:^(NSError *error) {
                    if (!error) {
                        [[iOSSocialServicesStore sharedServiceStore] registerAccount:self];
                    }
                    
                    if (self.authenticationHandler) {
                        self.authenticationHandler(error);
                        self.authenticationHandler = nil;
                    }
                }];
            }
        }];
    } else {
        [self fetchLocalUserDataWithCompletionHandler:^(NSError *error) {
            if (!error) {
                //
            }
            
            if (self.authenticationHandler) {
                self.authenticationHandler(error);
                self.authenticationHandler = nil;
            }
        }];
    }
}

- (NSString*)oAuthAccessToken
{
    return self.auth.accessToken;
}

- (void)logout
{
    [[Flickr sharedService] logout:self.auth forKeychainItemName:self.keychainItemName];
    
    self.auth = nil;
}

- (NSString*)userId
{
    return self.userID;
}

- (NSString*)username
{
    return self.alias;
}

- (NSString*)servicename
{
    return [Flickr sharedService].name;
}

@end
