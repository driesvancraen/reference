/*
Copyright (C) 2013 Electric Imp, Inc
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files 
(the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


// **********************************************************************************************************************************
class sensor {

    i2c       = null;
    pin_en_l  = null;
    pin_drain = null;
    addr      = null;
    ready     = false;
    name      = "sensor";
    static sensorlist = {};
    
    constructor(_i2c=null, _pin_en_l=null, _pin_drain=null, _addr=null) {
        i2c = _i2c;
		pin_en_l = _pin_en_l;
		pin_drain = _pin_drain;
        addr = _addr;
        ::last_activity <- time();
        
        if (i2c) i2c.configure(CLOCK_SPEED_400_KHZ);
		if (pin_en_l) pin_en_l.configure(DIGITAL_OUT);
		if (pin_drain) pin_drain.configure(DIGITAL_OUT);

        // Test the sensor and if its alive then setup a handler to execute all functions of the class
        if (test()) {
            sensorlist[name] <- this;
            agent.on(name, agent_event.bindenv(this));
        }
    }

	function enable() {
		if (pin_en_l) pin_en_l.write(0);
		if (pin_drain) pin_drain.write(1);
		imp.sleep(0.001);
	}

	function disable() {
		if (pin_en_l) pin_en_l.write(1);
		if (pin_drain) pin_drain.write(0);
	}

	function test() {
        if (i2c == null) {
            ready = false;  
        } else {
      		enable();
      		local t = i2c.read(addr, "", 1);
      		ready = (t != null);
      		disable();
        }
    
        return ready;
	}

    function get_nv(key) {
    	if (("nv" in getroottable()) && (key in ::nv)) {
            return ::nv[key];
		} else {
    	    return null;   
		}
    }
    
    function set_nv(key, value) {
        if (!("nv" in getroottable())) ::nv <- {};
        ::nv[key] <- value;
    }


    function dump_nv(root = null) {
        if ("nv" in getroottable()) {
            if (root == null) root = ::nv;
            foreach (k,v in root) {
                if (typeof v == "array" || typeof v == "table") {
                    log("NV: " + k + " => " + v)
                    dump_nv(v);
                } else {
                    log("NV: " + k + " => " + v)
                }
            }
        } else {
            log("NV: Not defined");
        }
        
    }
    
    
    function get_wake_reason() {
        
		switch (hardware.wakereason()) {
		case WAKEREASON_POWER_ON: return "power on"; 
		case WAKEREASON_TIMER: return "timer"; 
		case WAKEREASON_SW_RESET: return "software reset";
		case WAKEREASON_PIN1: return "pin1 interrupt";
		case WAKEREASON_NEW_SQUIRREL: return "new squirrel";
		default: return "unknown";
		}
    }
    
    
	function get_bootreason() {
        // log("GET bootreason: " + get_nv("reason"));
        return get_nv("reason");
	}


	function set_bootreason(_reason = null) {
        set_nv("reason", _reason);
        // log("SET bootreason to " + _reason);
	}
    
    function agent_event(data) {
        last_activity = time();
        if (data.method in this && typeof this[data.method] == "function") {
      
            // Formulate the function and the callback
            local method = this[data.method];
            local params = [this];
            local callback = remote_response(name, data.method).bindenv(this);
            
            if ("params" in data) {
                if (typeof data.params == "array") {
                    params.extend(data.params);
                } else {
                    params.push(data.params);
                }
            }
            params.push(callback);
        
            // Execute the function call with the parameters and callbacks
            try {
                method.acall(params);
            } catch (e) {
                log(format("Exception while executing '%s.%s': %s", name, data.method, e))
            }
        }
    }

    function reset() {
        if (i2c) {
            i2c.write(0x00,format("%c",RESET_VAL));
            imp.sleep(0.01);
        }
    }


	function sleep(dur = 600, delay = 0, callback = null) {

		switch (hardware.wakereason()) {
		case WAKEREASON_POWER_ON:
		case WAKEREASON_NEW_SQUIRREL:
			delay = delay >= 10 ? delay : 10;
			break;
		}

		server.log("Sleeping in " + delay + " for " + dur + ". Last wake reason: " + get_wake_reason());
		imp.wakeup(delay, function() {
			imp.onidle(function() {
				// Clearing the interrupt pins like this is a bit hacky but it gets the job done.
				// If squirrel had a destructor() function, I would prefer to do it there.
				if (i2c) i2c.read(addr, lis3dh.INT1_SRC, 1); 
				if (i2c) i2c.read(addr, lis3dh.TAP_SRC, 1); 

				server.expectonlinein(dur);
				imp.deepsleepfor(dur);
			}.bindenv(this))
		}.bindenv(this))

	}


    function remote_response(dev, method) {
        return function(data = null) {
            agent.send(dev + "." + method, data);
        }
    }
	
}

// **********************************************************************************************************************************
/* LIS3DH Ultra-low Power 3-axis Accelerometer
 * http://www.st.com/web/catalog/sense_power/FM89/SC444/PF250725
 *
 */
class lis3dh extends sensor {
    
    static CTRL_REG1     = "\x20";
    static CTRL_REG2     = "\x21";
    static CTRL_REG3     = "\x22";
    static CTRL_REG4     = "\x23";
    static CTRL_REG5     = "\x24";
    static CTRL_REG6     = "\x25";
    static DATA_X_L      = "\x28";
    static DATA_X_H      = "\x29";
    static DATA_Y_L      = "\x2A";
    static DATA_Y_H      = "\x2B";
    static DATA_Z_L      = "\x2C";
    static DATA_Z_H      = "\x2D";
    static INT1_CFG      = "\x30";
    static INT1_SRC      = "\x31";
    static INT1_THS      = "\x32";
    static INT1_DURATION = "\x33";
    static TAP_CFG       = "\x38";
    static TAP_SRC       = "\x39";
    static TAP_THS       = "\x3A";
    static TIME_LIMIT    = "\x3B";
    static TIME_LATENCY  = "\x3C";
    static TIME_WINDOW   = "\x3D";
    static WHO_AM_I      = "\x0F";
    static FLAG_SEQ_READ = "\x80";

    last_state = {x = null, y = null, z = null};
    
    static name = "accelerometer";
    
    constructor(_i2c, _addr = 0x30) {
        base.constructor(_i2c, null, null, _addr);
    }
    
    function stop(callback = null) {
        hardware.pin1.configure(DIGITAL_IN);
        set_bootreason();
        if (callback) callback();
    }


    function read(callback = null, initialise = true) {
        
        if (!ready) return null;
        
        // Configure settings of the accelerometer
        if (initialise) {
            i2c.write(addr, CTRL_REG1 + "\x47");  // Turn on the sensor, enable X, Y, and Z, ODR = 50 Hz
            i2c.write(addr, CTRL_REG2 + "\x00");  // High-pass filter disabled
            i2c.write(addr, CTRL_REG3 + "\x40");  // Interrupt driven to INT1 pad
            i2c.write(addr, CTRL_REG4 + "\x00");  // FS = 2g
            i2c.write(addr, CTRL_REG5 + "\x00");  // Interrupt Not latched
            i2c.write(addr, CTRL_REG6 + "\x00");  // Interrupt Active High (not actually used)
            i2c.read(addr, INT1_SRC, 1);          // Clear any interrupts
        }
        
        local data = i2c.read(addr, (DATA_X_L[0] | FLAG_SEQ_READ[0]).tochar(), 6);
        local x = 0, y = 0, z = 0;
        if (data != null) {
            x = (data[1] - (data[1]>>7)*256) / 64.0;
            y = (data[3] - (data[3]>>7)*256) / 64.0;
            z = (data[5] - (data[5]>>7)*256) / 64.0;
            
            if (callback) callback({x = x, y = y, z = z});
            return {x = x, y = y, z = z};
        }
        
        return null;        
    }


  function free_fall_detect(callback) {

        if (!ready) return null;

        // Setup the accelerometer for sleep-polling
        i2c.write(addr, CTRL_REG1 + "\xA7");        // Turn on the sensor, enable X, Y, and Z, ODR = 100 Hz
        i2c.write(addr, CTRL_REG2 + "\x00");        // High-pass filter disabled
        i2c.write(addr, CTRL_REG3 + "\x40");        // Interrupt driven to INT1 pad
        i2c.write(addr, CTRL_REG4 + "\x00");        // FS = 2g
        i2c.write(addr, CTRL_REG5 + "\x08");        // Interrupt latched
        i2c.write(addr, CTRL_REG6 + "\x00");        // Interrupt Active High
        i2c.write(addr, INT1_THS + "\x16");         // Set free-fall threshold = 350 mg
        i2c.write(addr, INT1_DURATION + "\x05");    // Set minimum event duration (5 samples @ 100hz = 50ms)
        i2c.write(addr, INT1_CFG + "\x95");         // Configure free-fall recognition
        i2c.read(addr, INT1_SRC, 1);                // Clear any interrupts

        // Record the mode as free_fall for boot checks
        set_bootreason(name + ".free_fall_detect");

        // Configure pin1 for handling the interrupt
        hardware.pin1.configure(DIGITAL_IN_WAKEUP, function() {

            // Handle only active high transitions
            if (hardware.pin1.read() == 1) {

                // Call the callback 
                callback();

                imp.wakeup(1, function() {
                    // Clear the interrupt after a small delay
                    i2c.read(addr, INT1_SRC, 1);
                }.bindenv(this));
            }
        }.bindenv(this));
    }


  function inertia_detect(callback) {

        if (!ready) return null;

        // Work out which axes to exclude
        local init_pos = read();
        local axes = { };
        axes.x <- (math.fabs(init_pos.x) < 0.5);
        axes.y <- (math.fabs(init_pos.y) < 0.5);
        axes.z <- (math.fabs(init_pos.z) < 0.5);
        axes.cfg <- ((axes.x ? 0x02 : 0x00) | (axes.y ? 0x08 : 0x00) | (axes.z ? 0x20 : 0x00)).tochar();
        // log(format("Initial orientation:  X: %0.02f, Y: %0.02f, Z: %0.02f  =>  0x%02x", init_pos.x, init_pos.y, init_pos.z, axes.cfg[0]));

        // Setup the accelerometer for sleep-polling
        i2c.write(addr, CTRL_REG1 + "\xA7");        // Turn on the sensor, enable X, Y, and Z, ODR = 100 Hz
        i2c.write(addr, CTRL_REG2 + "\x00");        // High-pass filter disabled
        i2c.write(addr, CTRL_REG3 + "\x40");        // Interrupt driven to INT1 pad
        i2c.write(addr, CTRL_REG4 + "\x00");        // FS = 2g
        i2c.write(addr, CTRL_REG5 + "\x08");        // Interrupt latched
        i2c.write(addr, CTRL_REG6 + "\x00");        // Interrupt Active High
        i2c.write(addr, INT1_THS + "\x20");         // Set movement threshold = 500 mg
        i2c.write(addr, INT1_DURATION + "\x00");    // Duration not relevant
        i2c.write(addr, INT1_CFG + axes.cfg);       // Configure intertia detection axis/axes
        i2c.read(addr, INT1_SRC, 1);                // Clear any interrupts

        // Record the mode as free_fall for boot checks
        set_bootreason(name + ".inertia_detect");

        // Configure pin1 for handling the interrupt
        hardware.pin1.configure(DIGITAL_IN_WAKEUP, function() {

            // Handle only active high transitions
            if (hardware.pin1.read() == 1) {

                // Call the callback 
                callback();

                imp.wakeup(0.5, function() {
                    // Clear the interrupt after a small delay
                    i2c.read(addr, INT1_SRC, 1);
                }.bindenv(this));
            }

        }.bindenv(this));
    }


  function movement_detect(callback) {

        if (!ready) return null;

        // Setup the accelerometer for sleep-polling
        i2c.write(addr, CTRL_REG1 + "\xA7");        // Turn on the sensor, enable X, Y, and Z, ODR = 100 Hz
        i2c.write(addr, CTRL_REG2 + "\x00");        // High-pass filter disabled
        i2c.write(addr, CTRL_REG3 + "\x40");        // Interrupt driven to INT1 pad
        i2c.write(addr, CTRL_REG4 + "\x00");        // FS = 2g
        i2c.write(addr, CTRL_REG5 + "\x00");        // Interrupt latched
        i2c.write(addr, CTRL_REG6 + "\x00");        // Interrupt Active High
        i2c.write(addr, INT1_THS + "\x10");         // Set movement threshold = ? mg
        i2c.write(addr, INT1_DURATION + "\x00");    // Duration not relevant
        i2c.write(addr, INT1_CFG + "\x6A");         // Configure intertia detection axis/axes - all three. Plus 6D.
        i2c.read(addr, INT1_SRC, 1);                // Clear any interrupts

        // Record the mode as free_fall for boot checks
        set_bootreason(name + ".movement_detect");

        // Configure pin1 for handling the interrupt
        hardware.pin1.configure(DIGITAL_IN_WAKEUP, function() {

            // Handle only active high transitions
            if (hardware.pin1.read() == 1) {

                // Call the callback 
                callback();
            }

        }.bindenv(this));
    }


  function position_detect(callback) {

        if (!ready) return null;

        // Setup the accelerometer for sleep-polling
        i2c.write(addr, CTRL_REG1 + "\xA7");        // Turn on the sensor, enable X, Y, and Z, ODR = 100 Hz
        i2c.write(addr, CTRL_REG2 + "\x00");        // High-pass filter disabled
        i2c.write(addr, CTRL_REG3 + "\x40");        // Interrupt driven to INT1 pad
        i2c.write(addr, CTRL_REG4 + "\x00");        // FS = 2g
        i2c.write(addr, CTRL_REG5 + "\x00");        // Interrupt latched
        i2c.write(addr, CTRL_REG6 + "\x00");        // Interrupt Active High
        i2c.write(addr, INT1_THS + "\x21");         // Set movement threshold = ? mg
        i2c.write(addr, INT1_DURATION + "\x21");    // Duration not relevant
        i2c.write(addr, INT1_CFG + "\xEA");         // Configure intertia detection axis/axes - all three. Plus AOI + 6D
        i2c.read(addr, INT1_SRC, 1);                // Clear any interrupts

        // Configure pin1 for handling the interrupt
        hardware.pin1.configure(DIGITAL_IN_WAKEUP, function() {

            // Handle only active high transitions
            if (hardware.pin1.read() == 1) {

                // Call the callback 
                callback();
            }

        }.bindenv(this));

        // Record the mode as free_fall for boot checks
        set_bootreason(name + ".position_detect");

    }


  function click_detect(callback) {

        if (!ready) return null;

        // Setup the accelerometer for sleep-polling
        i2c.write(addr, CTRL_REG1 + "\xA7");        // Turn on the sensor, enable X, Y, and Z, ODR = 100 Hz
        i2c.write(addr, CTRL_REG2 + "\x00");        // High-pass filter disabled
        i2c.write(addr, CTRL_REG3 + "\xC0");        // Interrupt driven to INT1 pad with CLICK detection enabled
        i2c.write(addr, CTRL_REG4 + "\x00");        // FS = 2g
        i2c.write(addr, CTRL_REG5 + "\x08");        // Interrupt latched
        i2c.write(addr, CTRL_REG6 + "\x00");        // Interrupt Active High
        i2c.write(addr, INT1_CFG + "\x00");         // Defaults
        i2c.write(addr, INT1_THS + "\x00");         // Defaults
        i2c.write(addr, INT1_DURATION + "\x00");    // Defaults
        i2c.write(addr, TAP_CFG + "\x10");          // Single click detection on Z
        i2c.write(addr, TAP_THS + "\x7F");          // Single click threshold
        i2c.write(addr, TIME_LIMIT + "\x10");       // Single click time limit
        i2c.read(addr, TAP_SRC, 1);                 // Clear any interrupts

        // Configure pin1 for handling the interrupt
        hardware.pin1.configure(DIGITAL_IN_WAKEUP, function() {

            // Handle only active high transitions
            local reason = i2c.read(addr, TAP_SRC, 1);
            if (hardware.pin1.read() == 1) {
                local xtap = (reason[0] & 0x01) == 0x01 ? 1 : 0;
                local ytap = (reason[0] & 0x02) == 0x02 ? 1 : 0;
                local ztap = (reason[0] & 0x04) == 0x04 ? 1 : 0;
                local sign = (reason[0] & 0x08) == 0x08 ? -1 : 1;
                
                // Call the callback 
                // log(format("Clickety clack: [X: %d, Y: %d, Z: %d, Sign: %d]", xtap, ytap, ztap, sign))
                callback();
            }
                
        }.bindenv(this));

        // Record the mode as free_fall for boot checks
        set_bootreason(name + ".click_detect");

    }
        
        
    function threshold(thresholds, callback) {
        // Read the accelerometer data
        read(function (res) {
            local state = clone last_state;
            
            if (!("axes" in thresholds) || thresholds.axes.toupper().find("X") != null) {
                if (res.x <= thresholds.low) state.x = "low";
                else if (res.x >= thresholds.high) state.x = "high";
                else state.x = "mid";
            }
            
            if (!("axes" in thresholds) || thresholds.axes.toupper().find("Y") != null) {
                if (res.y <= thresholds.low) state.y = "low";
                else if (res.y >= thresholds.high) state.y = "high";
                else state.y = "mid";
            }

            if (!("axes" in thresholds) || thresholds.axes.toupper().find("Z") != null) {
                if (res.z <= thresholds.low) state.z = "low";
                else if (res.z >= thresholds.high) state.z = "high";
                else state.z = "mid";
            }
            
            if (last_state.x != state.x || last_state.y != state.y || last_state.z != state.z) {
                last_state = clone state;
                callback(res);
            } else {
                imp.wakeup(0.1, function() {
                    threshold(thresholds, callback);
                }.bindenv(this))
            }
        }.bindenv(this))
    }


}