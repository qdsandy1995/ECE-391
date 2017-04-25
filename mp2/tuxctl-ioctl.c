/* tuxctl-ioctl.c
 *
 * Driver (skeleton) for the mp2 tuxcontrollers for ECE391 at UIUC.
 *
 * Mark Murphy 2006
 * Andrew Ofisher 2007
 * Steve Lumetta 12-13 Sep 2009
 * Puskar Naha 2013
 */

#include <asm/current.h>
#include <asm/uaccess.h>

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/miscdevice.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/spinlock.h>

#include "tuxctl-ld.h"
#include "tuxctl-ioctl.h"
#include "mtcp.h"

#define debug(str, ...) \
	printk(KERN_DEBUG "%s: " str, __FUNCTION__, ## __VA_ARGS__)


spinlock_t lock = SPIN_LOCK_UNLOCKED;
unsigned char button;
volatile int ack;
unsigned char LED[6];
char number_to_LED[] = {0xE7,0x06,0xCB,0x8F,0x2E,0xAD,0xED,0x86,0xEF,0xAE};  //0-9 number map to LED 
/************************ Protocol Implementation *************************/

/* tuxctl_handle_packet()
 * IMPORTANT : Read the header for tuxctl_ldisc_data_callback() in 
 * tuxctl-ld.c. It calls this function, so all warnings there apply 
 * here as well.
 * Button format: right left down up c b a start 
 */
void tuxctl_handle_packet (struct tty_struct* tty, unsigned char* packet)
{
    unsigned a, b, c;
	unsigned long flags;
    spin_lock_irqsave(&lock, flags);
    a = packet[0]; /* Avoid printk() sign extending the 8-bit */
    b = packet[1]; /* values when printing them. */
    c = packet[2];
	
	switch(a){                              // different cases depend on the opcode
	case MTCP_BIOC_EVENT:
	{

		 char left,down;
		 left = 0;
		 down = 0;
		 button = 0;
		 button = b & 0x0F;  
		 button = button | ((c & 0x0F) << 4); //Get RDLUCBAS
		 left=button & 0x20;
		 down=button & 0x40;
		 button=button & 0x9F;
         button &= 0x9F;   //Set D and L in Button to 0
         left = left << 1;
		 down = down >> 1;
		 button |= left;
		 button |= down;
         spin_unlock_irqrestore(&lock, flags);
		 return;

	}
	case MTCP_ACK:
	{

         ack = 0;                               //command received
		 spin_unlock_irqrestore(&lock, flags);
		 return;

	}
	case MTCP_RESET:
	{
		char buffer[1];
		buffer[0] = MTCP_BIOC_ON;                          // Enable Button interrupt-on-change.
		tuxctl_ldisc_put(tty,buffer,1);
		buffer[0] = MTCP_LED_USR;                         // Put the LED display into user-mode
		tuxctl_ldisc_put(tty,buffer,1);
		if(ack == 1)
		{
			return;
		}
		ack = 1;
		buffer[0] = MTCP_CLK_RUN;                   //Not sure if it's used'
		tuxctl_ldisc_put(tty,buffer,1);
		tuxctl_ldisc_put(tty,LED,6);                // restore the LED set up
        spin_unlock_irqrestore(&lock, flags);
		
	}
	default:
    		spin_unlock_irqrestore(&lock, flags);
    		return;
    }
    /*printk("packet : %x %x %x\n", a, b, c); */
}


/******** IMPORTANT NOTE: READ THIS BEFORE IMPLEMENTING THE IOCTLS ************
 *                                                                            *
 * The ioctls should not spend any time waiting for responses to the commands *
 * they send to the controller. The data is sent over the serial line at      *
 * 9600 BAUD. At this rate, a byte takes approximately 1 millisecond to       *
 * transmit; this means that there will be about 9 milliseconds between       *
 * the time you request that the low-level serial driver send the             *
 * 6-byte SET_LEDS packet and the time the 3-byte ACK packet finishes         *
 * arriving. This is far too long a time for a system call to take. The       *
 * ioctls should return immediately with success if their parameters are      *
 * valid.                                                                     *
 *                                                                            *
 ******************************************************************************/
int 
tuxctl_ioctl (struct tty_struct* tty, struct file* file, 
	      unsigned cmd, unsigned long arg)
{
    switch (cmd) {
	case TUX_INIT:
	{
		unsigned long flags;
		char buffer[1];
		buffer[0] = MTCP_BIOC_ON;                          // Enable Button interrupt-on-change.
		tuxctl_ldisc_put(tty,buffer,1);
		buffer[0] = MTCP_LED_USR;                         // Put the LED display into user-mode
		tuxctl_ldisc_put(tty,buffer,1);
		buffer[0] = MTCP_CLK_RUN;                   //Not sure if it's used'
		tuxctl_ldisc_put(tty,buffer,1);
        spin_lock_irqsave(&lock, flags);
		button = 0xFF;                                     //lock global variable
		spin_unlock_irqrestore(&lock, flags);
   
        return 0;
	
	}
	case TUX_BUTTONS:
	{

	   char output;	
       unsigned long flags;
	   int* ptr = (int*)arg; 
	   spin_lock_irqsave(&lock, flags);
	   output = button;
	   spin_unlock_irqrestore(&lock, flags);
	   if(ptr == NULL || copy_to_user(ptr,&output,1))          //feed button to user
	   {
		   return -EINVAL;
	   }
	   else
	   {
           return 0;   
	   }	 
	     
	}
	case TUX_SET_LED:
	{
       int LED_Mask;
	   int i;
	   int DP;                // decimal points to turn on
	   unsigned long flags;
	   int LED_Display[4];              //Minute,Minute,Second,Second	
	  
	   int bitmask = 1;   
	   
	   spin_lock_irqsave(&lock, flags);   //lock write process in case of reset interrupts
	   LED_Mask = ((arg >> 16) & 0x000F);      // LED to turn on 
	  
	   LED[0] = MTCP_LED_SET;
	   LED_Display[3] = (arg & 0x0000FFFF) >> 12;           //Get Mins and Secs
	   LED_Display[2] = (arg & 0x00000FFF) >> 8;
       LED_Display[1] = (arg & 0x000000FF) >> 4;
	   LED_Display[0] = (arg & 0x0000000F);
	   LED[1] = 0x0F;                                      
	   DP = (arg >> 24) & 0x0F;                           
	   for(i = 2; i < 6 ; i++)
	   {
		   if((LED_Mask & bitmask) != 0)
		   {
              LED[i] = number_to_LED[LED_Display[i-2]];   //Conver number to LED layout
		      if((DP>>(i-2))&0x1)
		      {
			     LED[i] |= 0x10;               //Set the decimal points
		      }
			  bitmask = bitmask << 1;
	       } 
	   }
	   if(ack == 1)
	   {
          return -EINVAL;                      //check command recieved?
	   }
	   tuxctl_ldisc_put(tty,LED,6);
	 
	   ack = 1;
       spin_unlock_irqrestore(&lock, flags);
	   return 0;
	  
	}
	case TUX_LED_ACK:
	{
        return 0;
	}
	case TUX_LED_REQUEST:
	{
         return 0;
	}
	case TUX_READ_LED:
	{
         return 0;
	}
	default:
	    return -EINVAL;
    }
}

