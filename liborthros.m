//
//  liborthros.m
//  liborthros
//
//  Created by haifisch on 7/3/15.
//  Copyright (c) 2015 Haifisch. All rights reserved.
//

#import "liborthros.h"
#warning I hate warnings, but remind me to change this back to NO.
#define DEVELOPMENT YES
@implementation liborthros {
    NSURL *apiAddress;
    NSString *UUID;
}

#pragma mark orthros init

- (id)initWithUUID:(NSString *)uuid {
    if (DEVELOPMENT) {
        return [self initWithAPIAddress:@"https://development.orthros.ninja" withUUID:uuid];
    }
    return [self initWithAPIAddress:@"https://api.orthros.ninja" withUUID:uuid];
}

- (id)initWithAPIAddress:(NSString *)url withUUID:(NSString*)uuid {
    self = [super init];
    if (self) {
        apiAddress = [NSURL URLWithString:url];
        UUID = uuid;
    }
    return self;
}

#pragma mark orthos message functions

// Read message for ID, response is encrypted.
- (NSString *)readMessageWithID:(NSInteger *)msg_id {
    NSString *action = @"get";
    NSString *urlString = [NSString stringWithFormat:@"%@?action=%@&msg_id=%ld&UUID=%@", apiAddress, action, (long)msg_id, UUID];
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlString]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:0 error:&error];
        if (error)
            NSLog(@"liborthros; JSON parsing error: %@", error);
        NSString *fixedString = [responseParsed[@"msg"][@"msg"] stringByReplacingOccurrencesOfString:@" " withString:@"+"];
        return fixedString;
    }
    return nil;
}

// Get sender for message ID
- (NSString *)senderForMessageID:(NSInteger *)msg_id {
    NSString *action = @"get";
    NSString *urlString = [NSString stringWithFormat:@"%@?action=%@&msg_id=%ld&UUID=%@", apiAddress, action, (long)msg_id, UUID];
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlString]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:0 error:&error];
        if (error)
            NSLog(@"liborthros; JSON parsing error: %@", error);
        NSString *senderString = responseParsed[@"msg"][@"sender"];
        return senderString;
    }
    return nil;
}

// Get all messages in the user's queue.
- (NSMutableArray *)messagesInQueue {
    NSMutableArray *returnedArray = [[NSMutableArray alloc] init];
    NSString *action = @"list";
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID]]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:NSJSONReadingMutableContainers error:&error];
        returnedArray = responseParsed[@"msgs"];
        if (error)
            NSLog(@"liborthros; JSON parsing error: %@", error);
    }
    return returnedArray;
}

// Delete message for ID, returns YES for a sucessful deletion or NO for unsucessful
- (BOOL)deleteMessageWithID:(NSInteger *)msg_id withKey:(NSString *)key {
    NSString *action = @"delete_msg";
    NSString *post = [NSString stringWithFormat:@"key=%@",key];
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@&msg_id=%ld", apiAddress, action, UUID, (long)msg_id]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;
    __block BOOL deletionResponse;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSLog(@"Status code: %li", (long)((NSHTTPURLResponse *)response).statusCode);
            NSMutableDictionary *parsedDict = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] mutableCopy];
            if ([parsedDict[@"error"] integerValue] == 1 || parsedDict == nil) {
                deletionResponse = NO;
            }else {
                deletionResponse = YES;
            }
        } else {
            deletionResponse = NO;
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return deletionResponse;
}

// Send encrypted message to a user's ID
- (BOOL)sendMessage:(NSString *)crypted_message toUser:(NSString *)to_id withKey:(NSString *)key {
    NSDictionary* jsonDict = @{@"sender":UUID,@"msg":crypted_message};
    NSData* json = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
    NSString *jsonStr = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *post = [NSString stringWithFormat:@"msg=%@&key=%@", jsonStr, key];
    NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    NSString *action = @"send";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@&receiver=%@", apiAddress, action, UUID, to_id]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;
    __block BOOL sendResponse;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSLog(@"Status code: %li", (long)((NSHTTPURLResponse *)response).statusCode);
            NSMutableDictionary *parsedDict = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] mutableCopy];
            if ([parsedDict[@"error"] integerValue] == 1 || parsedDict == nil) {
                sendResponse = NO;
            }else {
                sendResponse = YES;
            }

        } else {
            NSLog(@"liborthros; Error: %@", error.localizedDescription);
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return sendResponse;
}

#pragma mark nonce managment

// Get onetime key
- (NSString *)genNonce {
    NSString *returnedKey = [[NSString alloc] init];
    NSString *action = @"gen_key";
    NSString *url = [NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID];
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:NSJSONReadingMutableContainers error:&error];
        if (!error)
            returnedKey = responseParsed[@"key"];
    }
    return returnedKey;
}

#pragma mark General UUID queries

// Check if UUID exists
- (BOOL)checkForUUID {
    NSString *action = @"check";
    NSString *url = [NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID];
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:NSJSONReadingMutableContainers error:&error];
        if (error)
            NSLog(@"liborthros; JSON parsing error: %@", error);
        if ([responseParsed[@"error"] intValue] != 1) {
            return YES;
        }else {
            return NO;
        }
    }
    return NO;
}

// Submit the user's public key to the server
- (BOOL)uploadPublicKey:(NSString *)pub {
    NSString *post = [NSString stringWithFormat:@"pub=%@",[self  base64String:pub]];
    NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    NSString *action = @"upload";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;
    __block BOOL uploadResponse;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSError *error;
            NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
            if (error)
                NSLog(@"liborthros; JSON parsing error: %@", error);
            if ([responseParsed[@"error"] intValue] != 1) {
                uploadResponse = YES;
            }else {
                uploadResponse = NO;
            }
        } else {
            uploadResponse = NO;
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return uploadResponse;
}

// Submit the user's public key to the server
-(BOOL)submitToken:(NSString *)device_token {
    NSString *post = [NSString stringWithFormat:@"token=%@",device_token];
    NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    NSString *action = @"submit_token";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;
    __block BOOL uploadResponse;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSError *error;
            NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
            if (error)
                NSLog(@"liborthros; JSON parsing error: %@", error);
            if ([responseParsed[@"error"] intValue] != 1) {
                uploadResponse = YES;
            }else {
                uploadResponse = NO;
            }
        } else {
            uploadResponse = NO;
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return uploadResponse;
}

// Obliterate a user
- (BOOL)obliterateUserForID:(NSString *)uuid withKey:(NSString *)key {
    NSString *post = [NSString stringWithFormat:@"key=%@", key];
    NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    NSString *action = @"obliterate";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?action=%@&UUID=%@", apiAddress, action, UUID]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;
    __block BOOL sendResponse;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSLog(@"Status code: %li", (long)((NSHTTPURLResponse *)response).statusCode);
            NSMutableDictionary *parsedDict = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] mutableCopy];
            if ([parsedDict[@"error"] integerValue] == 1 || parsedDict == nil) {
                sendResponse = NO;
            }else {
                sendResponse = YES;
            }
            
        } else {
            NSLog(@"liborthros; Error: %@", error.localizedDescription);
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return sendResponse;
}

// Download public key for user's ID
-(NSString *)publicKeyForUserID:(NSString *)user_id {
    NSString *action = @"download";
    NSString *url = [NSString stringWithFormat:@"%@?action=%@&UUID=%@&receiver=%@", apiAddress, action, UUID, user_id];
    NSData *queryData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    if (queryData) {
        NSError *error;
        NSMutableDictionary *responseParsed = [NSJSONSerialization JSONObjectWithData:queryData options:NSJSONReadingMutableContainers error:&error];
        NSData *base64 = [[NSData alloc] initWithBase64EncodedString:responseParsed[@"pub"] options:0];
        NSString *returnedPub = [[NSString alloc] initWithData:base64 encoding:NSUTF8StringEncoding];
        // what the hell
        // cut it up, fix it, put it back together. :) fuck this
        returnedPub = [returnedPub stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@""];
        returnedPub = [returnedPub stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@""];
        returnedPub = [returnedPub stringByReplacingOccurrencesOfString:@" " withString:@"+"];
        returnedPub = [NSString stringWithFormat:@"-----BEGIN PUBLIC KEY-----%@-----END PUBLIC KEY-----", returnedPub];
        if (error)
            NSLog(@"liborthros; JSON parsing error: %@", error);
        if (returnedPub)
            return returnedPub;
    }
    return nil;
}

// Local base64 string function
- (NSString *)base64String:(NSString *)str
{
    NSData *theData = [str dataUsingEncoding: NSASCIIStringEncoding];
    const uint8_t* input = (const uint8_t*)[theData bytes];
    NSInteger length = [theData length];
    
    static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    
    NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    uint8_t* output = (uint8_t*)data.mutableBytes;
    
    NSInteger i;
    for (i=0; i < length; i += 3) {
        NSInteger value = 0;
        NSInteger j;
        for (j = i; j < (i + 3); j++) {
            value <<= 8;
            
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }
        
        NSInteger theIndex = (i / 3) * 4;
        output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
        output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
        output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
        output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
    }
    
    return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
}

@end
