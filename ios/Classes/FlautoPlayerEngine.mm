/*
 * Copyright 2018, 2019, 2020, 2021 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the Mozilla Public License version 2 (MPL2.0),
 * as published by the Mozilla organization.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * MPL General Public License for more details.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


//
//  PlayerEngine.h
//  Pods
//
//  Created by larpoux on 03/09/2020.
//
#include <libkern/OSAtomic.h>

#import "Flauto.h"
#import "FlautoPlayerEngine.h"
#import "FlautoPlayer.h"

@implementation AudioPlayerFlauto
{
        FlautoPlayer* flautoPlayer; // Owner
        AVAudioPlayer* player;
}

       - (AVAudioPlayer*) getAudioPlayer
       {
                return player;
       }

        - (void) setAudioPlayer: (AVAudioPlayer*)thePlayer
        {
                player = thePlayer;
        }



       - (AudioPlayerFlauto*)init: (FlautoPlayer*)owner
       {
                flautoPlayer = owner;
                return [super init];
       }

       -(void) startPlayerFromBuffer: (NSData*) dataBuffer
       {
                NSError* error = [[NSError alloc] init];
                [self setAudioPlayer:  [[AVAudioPlayer alloc] initWithData: dataBuffer error: &error]];
                [self getAudioPlayer].delegate = flautoPlayer;
       }

       -(void)  startPlayerFromURL: (NSURL*) url codec: (t_CODEC)codec channels: (int)numChannels sampleRate: (long)sampleRate

       {
                [self setAudioPlayer: [[AVAudioPlayer alloc] initWithContentsOfURL: url error: nil] ];
                [self getAudioPlayer].delegate = flautoPlayer;
        }


       -(long)  getDuration
       {
                double duration =  [self getAudioPlayer].duration;
                return (long)(duration * 1000.0);
       }

       -(long)  getPosition
       {
                double position = [self getAudioPlayer].currentTime ;
                return (long)( position * 1000.0);
       }

       -(void)  stop
       {
                [ [self getAudioPlayer] stop];
                [self setAudioPlayer: nil];
       }

        -(bool)  play
        {
                // This fixes the audio output to the speaker (LAPSI fix)
                NSError *error = nil;
                [[AVAudioSession sharedInstance]
                setCategory:AVAudioSessionCategoryPlayAndRecord
                withOptions: AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionAllowBluetooth
                error:&error];
                
                bool b = [ [self getAudioPlayer] play];
                return b;
        }


       -(bool)  resume
       {
                bool b = [ [self getAudioPlayer] play];
                return b;
       }

       -(bool)  pause
       {
                [ [self getAudioPlayer] pause];
                return true;
       }


       -(bool)  setVolume: (double) volume fadeDuration:(NSTimeInterval)fadeDuration // volume is between 0.0 and 1.0
       {
               if (fadeDuration == 0)
                     [ [self getAudioPlayer] setVolume: volume ];
               else
                       [ [self getAudioPlayer] setVolume: volume fadeDuration: fadeDuration];
               return true;
       }


        -(bool)  setSpeed: (double) speed // speed is between 0.0 and 1.0 to go slower
        {
                [self getAudioPlayer].enableRate = true ; // Probably not always !!!!
                [self getAudioPlayer].rate = speed ;
                return true;
        }

       -(bool)  seek: (double) pos
       {
                [self getAudioPlayer].currentTime = pos / 1000.0;
                return true;
       }

       -(t_PLAYER_STATE)  getStatus
       {
                if (  [self getAudioPlayer] == nil )
                        return PLAYER_IS_STOPPED;
                if ( [ [self getAudioPlayer] isPlaying])
                        return PLAYER_IS_PLAYING;
                return PLAYER_IS_PAUSED;
       }


        - (int) feed: (NSData*)data
        {
                return -1;
        }

@end


// -----------------------------------------------------streaming engine below----------------------------------------------------------------------------------------------------------


@implementation AudioEngine
{
        FlautoPlayer* flutterSoundPlayer; // Owner
        AVAudioEngine* engine;
        AVAudioPlayerNode* playerNode;
        AVAudioFormat* playerFormat;
        AVAudioFormat* outputFormat;
        AVAudioOutputNode* outputNode;
        AVAudioConverter* converter;
        CFTimeInterval mStartPauseTime ; // The time when playback was paused
	CFTimeInterval systemTime ; //The time when  StartPlayer() ;
        double mPauseTime ; // The number of seconds during the total Pause mode
        long m_sampleRate ; // >= 4 kHz
        int  m_numChannels; // 2
        int64_t m_inBuffer; // number of feed() blocks of data in the audio buffer
}
       - (AudioEngine*)init: (FlautoPlayer*)owner codec:(t_CODEC)codec
       {
                flutterSoundPlayer = owner;
                engine = [[AVAudioEngine alloc] init];
                outputNode = [engine outputNode];
           
                if (@available(iOS 13.0, *)) {
                    if ([flutterSoundPlayer isVoiceProcessingEnabled]) {
                        NSError* err;
                        if (![outputNode setVoiceProcessingEnabled:YES error:&err]) {
                           [flutterSoundPlayer logDebug:[NSString stringWithFormat:@"error enabling voiceProcessing => %@", err]];
                        } else {
                            [flutterSoundPlayer logDebug: @"VoiceProcessing enabled"];
                        }
                    }
                } else {
                   [flutterSoundPlayer logDebug: @"WARNING! VoiceProcessing is only available on iOS13+"];
                }
               
                outputFormat = [outputNode inputFormatForBus: 0];
                playerNode = [[AVAudioPlayerNode alloc] init];

                [engine attachNode: playerNode];

                [engine connect: playerNode to: outputNode format: outputFormat];
                bool b = [engine startAndReturnError: nil];
                if (!b)
                {
                        [flutterSoundPlayer logDebug: @"Cannot start the audio engine"];
                }

                mPauseTime = 0.0; // Total number of seconds in pause mode
		mStartPauseTime = -1; // Not in paused mode
		systemTime = CACurrentMediaTime(); // The time when started
                return [super init];
       }

       -(void) startPlayerFromBuffer: (NSData*) dataBuffer
       {
                 [self feed: dataBuffer] ;
       }


       -(void)  startPlayerFromURL: (NSURL*) url codec: (t_CODEC)codec channels: (int)numChannels sampleRate: (long)sampleRate
       {
                assert(url == nil || url ==  (id)[NSNull null]);
                m_sampleRate = sampleRate;
                m_numChannels= numChannels;
                m_inBuffer = 0;
       }

        // now returns the number of feed() calls that are not yet played out by the audio device
       -(long)  getDuration
       {
		return (long) (self->m_inBuffer);
       }

       -(long)  getPosition
       {
		double time ;
		if (mStartPauseTime >= 0) // In pause mode
			time =   mStartPauseTime - systemTime - mPauseTime ;
		else
			time = CACurrentMediaTime() - systemTime - mPauseTime;
		return (long)(time * 1000);
       }

       -(void)  stop
       {

                if (engine != nil)
                {
                        if (playerNode != nil)
                        {
                                [playerNode stop];
                                // Does not work !!! // [engine detachNode:  playerNode];
                                playerNode = nil;
                         }
                        [engine stop];
                        engine = nil;
                    
                        if (converter != nil)
                        {
                            converter = nil; // ARC will dealloc the converter (I hope ;-) )
                        }
                }
       }

        -(bool) play
        {
                [playerNode play];
                return true;

        }
       -(bool)  resume
       {
		if (mStartPauseTime >= 0)
			mPauseTime += CACurrentMediaTime() - mStartPauseTime;
		mStartPauseTime = -1;

		[playerNode play];
                return true;
       }

       -(bool)  pause
       {
		mStartPauseTime = CACurrentMediaTime();
		[playerNode pause];
                return true;
       }


       -(bool)  seek: (double) pos
       {
                return false;
       }

       -(int)  getStatus
       {
                if (engine == nil)
                        return PLAYER_IS_STOPPED;
                if (mStartPauseTime > 0)
                        return PLAYER_IS_PAUSED;
                if ( [playerNode isPlaying])
                        return PLAYER_IS_PLAYING;
                return PLAYER_IS_PLAYING; // ??? Not sure !!!
       }

        - (int) feed: (NSData*)data
        {
                const int maxUpsampleRatio = 12; // enough for playing 4kHz on an 48kHz audio device

                int ln = (int)[data length];
                int frameLength = ln / 2 / 2; /* stereo pcm16 */;

                AVAudioChannelLayout *chLayout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Stereo];
                playerFormat = [[AVAudioFormat alloc]
                        initWithCommonFormat: AVAudioPCMFormatInt16
                        sampleRate: (double)m_sampleRate
                        // channels: m_numChannels // ooh, it is made implicit in channelLayout
                        interleaved: YES
                        channelLayout: chLayout];

                AVAudioPCMBuffer* thePCMInputBuffer =  [[AVAudioPCMBuffer alloc] initWithPCMFormat: playerFormat frameCapacity: frameLength];
                memcpy((unsigned char*)(thePCMInputBuffer.int16ChannelData[0]), [data bytes], ln);
                thePCMInputBuffer.frameLength = frameLength;
                static bool hasData = true;
                hasData = true;
                AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer*(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus)
                {
                        *outStatus = hasData ? AVAudioConverterInputStatus_HaveData : AVAudioConverterInputStatus_NoDataNow;
                        hasData = false;
                        return thePCMInputBuffer;
                };

                AVAudioPCMBuffer* thePCMOutputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat: outputFormat frameCapacity: maxUpsampleRatio*frameLength];
                thePCMOutputBuffer.frameLength = 0;

                if (converter == nil)
                {
                        converter = [[AVAudioConverter alloc]initFromFormat: playerFormat toFormat: outputFormat];
                }

                NSError* error;
                [converter convertToBuffer: thePCMOutputBuffer error: &error withInputFromBlock: inputBlock];

//                 printf("m_inBuffer = %lld, err = %p, in_fs = %lf, in_ch = %d, in_len = %d, out_fs = %lf, out_ch = %d, out_len = %d\n",
//                        m_inBuffer, error,
//                        playerFormat.sampleRate, playerFormat.channelCount, thePCMInputBuffer.frameLength,
//                        outputFormat.sampleRate, outputFormat.channelCount, thePCMOutputBuffer.frameLength);

                @synchronized(self) {
                    self->m_inBuffer += 1;
                }

                [playerNode scheduleBuffer: thePCMOutputBuffer  completionHandler: ^(void) {
                    @synchronized(self) {
                        self->m_inBuffer -= 1;
                    }
                }];

                return ln;
         }

-(bool)  setVolume: (double) volume fadeDuration: (NSTimeInterval)fadeDuration// TODO
{
        return true; // TODO
}

- (bool) setSpeed: (double) speed
{
        return true; // TODO
}


@end

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------


@implementation AudioEngineFromMic
{
        FlautoPlayer* flutterSoundPlayer; // Owner
        AVAudioEngine* engine;
        AVAudioPlayerNode* playerNode;
        AVAudioFormat* playerFormat;
        AVAudioFormat* outputFormat;
        AVAudioOutputNode* outputNode;
        CFTimeInterval mStartPauseTime ; // The time when playback was paused
	CFTimeInterval systemTime ; //The time when  StartPlayer() ;
        double mPauseTime ; // The number of seconds during the total Pause mode
        NSData* waitingBlock;
        long m_sampleRate ;
        int  m_numChannels;
}

       - (AudioEngineFromMic*)init: (FlautoPlayer*)owner
       {
                flutterSoundPlayer = owner;
                waitingBlock = nil;
                engine = [[AVAudioEngine alloc] init];
                
                AVAudioInputNode* inputNode = [engine inputNode];
                outputNode = [engine outputNode];
                outputFormat = [outputNode inputFormatForBus: 0];
                
                [engine connect: inputNode to: outputNode format: outputFormat];
                return [super init];
       }
       

       -(void) startPlayerFromBuffer: (NSData*) dataBuffer
       {
       }
        static int ready2 = 0;

       -(long)  getDuration
       {
		return [self getPosition]; // It would be better if we add what is in the input buffers and not still played
       }

       -(long)  getPosition
       {
		double time ;
		if (mStartPauseTime >= 0) // In pause mode
			time =   mStartPauseTime - systemTime - mPauseTime ;
		else
			time = CACurrentMediaTime() - systemTime - mPauseTime;
		return (long)(time * 1000);
       }

       -(void)  startPlayerFromURL: (NSURL*) url codec: (t_CODEC)codec channels: (int)numChannels sampleRate: (long)sampleRate
       {
                assert(url == nil || url ==  (id)[NSNull null]);

                m_sampleRate = sampleRate;
                m_numChannels= numChannels;

                mPauseTime = 0.0; // Total number of seconds in pause mode
		mStartPauseTime = -1; // Not in paused mode
		systemTime = CACurrentMediaTime(); // The time when started
                ready2 = 0;
       }


       -(void)  stop
       {

                if (engine != nil)
                {
                         [engine stop];
                        engine = nil;
                }
       }

        -(bool) play
        {
                bool b = [engine startAndReturnError: nil];
                if (!b)
                {
                        [flutterSoundPlayer logDebug: @"Cannot start the audio engine"];
                }
                return b;
        }

       -(bool)  resume
       {
                return false;
       }

       -(bool)  pause
       {
                return false;
       }


       -(bool)  seek: (double) pos
       {
                return false;
       }

       -(int)  getStatus
       {
                if (engine == nil)
                        return PLAYER_IS_STOPPED;
                return PLAYER_IS_PLAYING; // ??? Not sure !!!
       }


        -(bool)  setVolume: (double) volume fadeDuration: (NSTimeInterval) fadeDuration // TODO
        {
                return true; // TODO
        }

        -(bool)  setSpeed: (double) speed // TODO
        {
                return true; // TODO
        }

      - (int) feed: (NSData*)data
       {
        return 0;
       }


//-------------------------------------------------------------------------------------------------------------------------------------------



@end
