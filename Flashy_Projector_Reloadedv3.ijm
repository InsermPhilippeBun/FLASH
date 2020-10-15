// -----------------------------------------------------------
// Initialization

// --- RESET RESULT TABLE
run("Clear Results");
// --- RESET THE LOG
print("\\Clear");
// --- CLOSE ALL IMAGES
run("Close All");
// --- RESET ROI MANAGER IF NECESSARY
if (isOpen("ROI Manager")) { 
	roiManager("reset");
	roiManager("Show All with labels");
} else {
	roiManager("show none");
	roiManager("Show All with labels");
}
// --- OTHERS
run("Brightness/Contrast...");
setTool("point");
setForegroundColor(255, 255, 255); setBackgroundColor(0, 0, 0);
run("Set Measurements...", "area centroid center perimeter shape feret's limit redirect=None decimal=3");

// -----------------------------------------------------------
// Starting Point

// --- OPENING FILE AND CREATING FOLDER
open();
name_file = File.nameWithoutExtension;
dir = getDirectory("Saving directory");
save_folder = dir + name_file + "_results/";
if ( File.exists(save_folder) < 1 ) File.makeDirectory(save_folder);

raw_stack = getImageID(); run("Set... ", "zoom=33");

// --- PREPARING THE STACK
run("8-bit"); run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
getDimensions(width, height, channels, slices, frames);
size_h = height; size_w = width; number_frames = nSlices();
trim = 5; //number of slices to be removed 
radius = 5; 
	
// --- TRIM IN SPACE
makeRectangle(60,60, size_w-120, size_h-120); // frame of 60pixels to be excluded
run("Crop");   
// --- TRIM IN TIME
begin_trim = trim;
end_trim = number_frames - trim; 
run("Slice Keeper", "first=begin_trim last=end_trim increment=1"); run("Set... ", "zoom=33");

selectImage(raw_stack); close();
trim_stack = getImageID();


//--------------------------------------------------
// Bleaching Correction

// ---Initialization
Stack.getDimensions(width, height, channels, slices, frames);
total_size = nSlices();
// --- TABLE
ratio_data = newArray(total_size);
// --- INTERROGATION BOX
Dialog.create("Experiment settings");
Dialog.addCheckbox("Electrical stimulation?", false);
Dialog.show();
Addition = Dialog.getCheckbox();


// --- Case Scenarii
// --- Electrical Stimulation: YES
if (Addition) {
	// reducing the interrogation size window
	window_low = floor((1/3)*total_size);
	window_high = round((2/3)*total_size);
	
	setBatchMode(true);
	run("Duplicate...", "duplicate range=window_low-window_high"); temp_stack = getImageID();
	run("Plot Z-axis Profile"); Plot.setStyle(0, "red,none,1.0,Connected Circles"); profile_plot = getImageID();
	selectImage(temp_stack); close();
	setBatchMode(false);

	// manual peak selection
	waitForUser("Addition","Pinpoint the highest peak of intensity during the experiment.\nLeft click to exit.");
	leftButton=16; rightButton=4; x2=-1; y2=-1; z2=-1; flags2=-1; 
	getCursorLoc(x, y, z, flags); 
	Outclick = false; 
	while (flags&rightButton==0){ 
		getCursorLoc(x, y, z, flags);      
		if (flags&leftButton!=0) { // Wait for it to be released 
			Outclick = true; 
        	} else if (Outclick) {
        	Outclick = false;
        	if (x!=x2 || y!=y2 || z!=z2 || flags!=flags2) {
        		toScaled(x, y);
        		setOption("DisablePopupMenu", true);
           		x_data = x; 
            }
		}
	}
	
	// --- Backdoor if there is no apparent stimulation
	Dialog.create("MACRO BACKDOOR");
	Dialog.addCheckbox("Would you like to continue?", false);
	Dialog.show();
	Proceeding = Dialog.getCheckbox();
	if (Proceeding == false) { exit("bye") };

	selectImage(profile_plot); close();
	
	split_point = window_low + x_data -1; // Timepoint-centered window to be removed for fitting procedure
	removal_points = 17;
	split_window_low = round(split_point -removal_points); // End of the 1st stack - around 5sec
	split_window_high = floor(split_point +removal_points) ; // Beginning of the 2nd stack -around 5sec

// --- Electrical Stimulation: NO
} else {
	split_window_low = 1; //no change
	split_window_high = total_size; //no change
}
run("Set... ", "zoom=33");

//--------------------------------------------------
// --- FITTING PROCEDURE
selectImage(trim_stack);

// --- Case Scenarii
	// --- Electrical Stimulation: YES
if (Addition) {
	run("Duplicate...", "duplicate range=1-split_window_low"); 
	first_raw_stack = getImageID(); rename("First_stack"); run("Set... ", "zoom=33"); first_length = nSlices();
	selectImage(trim_stack); run("Duplicate...", "duplicate range=split_window_high-total_size"); 
	second_raw_stack = getImageID(); rename("Second_stack"); run("Set... ", "zoom=33"); second_length = nSlices();

	selectImage(first_raw_stack);
	run("Plot Z-axis Profile"); Plot.getValues(x,y); close();
	biexp = "y = a + b*exp(-(c*x)) + d*exp(-(e*x))";
	initialGuesses = newArray(1, 1, 1, 1, 1);
	Fit.doFit(biexp, x, y, initialGuesses); Fit.plot; Fit.logResults; Fit_profile = getImageID(); rename("Fit-first");
	width_first = getWidth(); height_first = getHeight();
	
	Offset = Fit.p(0); Coeff_1 = Fit.p(1); Coeff_2 = Fit.p(3);
	Tau_1 = Fit.p(2); Tau_2 = Fit.p(4); R_2 = Fit.rSquared;

	selectImage(second_raw_stack);
	run("Plot Z-axis Profile"); Plot.getValues(x_2,y_2); Second_stack_profile = getImageID(); run("RGB Color"); rename("Raw-second"); run("RGB Color");
	width_second = getWidth(); height_second = getHeight();

	if (width_first > width_second) {
		width = width_first;	
	} else {
		width = width_second;
	}
	if (height_first > height_second) {
		height = height_first;	
	} else {
		height = height_second;
	}
	selectImage(Second_stack_profile); run("Size...", "width=width height=height depth=1 average interpolation=None"); run("RGB Color"); 
	run("Combine...", "stack1=Fit-first stack2=Raw-second"); 
	saveAs("tiff", save_folder + "Profiles -Split stack"); Combined_profile = getImageID();

	Plot.create("Fit behavior", "Slice", "Intensity");
	x_FIT = newArray(first_length+second_length); y_FIT = newArray(first_length+second_length);
	extensionX = x.length;
	for (i=0; i <x_2.length; i++) {
		x_2 [i] = x_2[i]+extensionX;
	}
	for (i=0; i<first_length+second_length; i++){
		x_FIT [i] = i+1;
		y_FIT [i] = Fit.f(i);
	}
	x_all = Array.concat(x,x_2); y_all = Array.concat(y,y_2);
	Plot.add("connected circle", x_all, y_all); Plot.setStyle(0, "black,none,1.0,Connected Circles");
	Plot.add("connected circle", x_FIT, y_FIT); Plot.setStyle(1, "red,red,1.0,Connected Circles");
	Plot.show();
	saveAs("tiff", save_folder + "Fit behavior");
	Fit_behavior_ALL = getImageID();

	
	waitForUser("Fit Review","Review the Fitting process.\nPress OK to proceed.");
	Dialog.create("MACRO FIT BACKDOOR");
	Dialog.addCheckbox("Would you like to proceed with bleaching correction?", false);
	Dialog.show();
	Fit_proceeding = Dialog.getCheckbox();
	selectImage(Combined_profile); close();
	selectImage(Fit_behavior_ALL); close();
		
	// --- Electrical Stimulation: YES
	// --- Fit: YES
	if (Fit_proceeding) {

		reference_ratio = Fit.f(x[0]); // at time 0
		x_data = newArray(x.length);
		
		for (j = 0; j < x.length; j++){
			x_data [j] = Fit.f(x[j]);
			ratio_data[j] = reference_ratio/Fit.f(x[j]);
		}
	
		size_second_stack = total_size - split_window_high +1;
		x_data_second = newArray(size_second_stack);
		ratio_data_second = newArray(size_second_stack);
	
		for (k = split_window_high; k <= total_size; k++){
			x_data_second[k-split_window_high] = Fit.f(k);
			ratio_data_second[k-split_window_high] = reference_ratio/Fit.f(k);
		}

		// --- CORRECTION ON DUPLICATED STACK
			// --- First stack
		selectImage(first_raw_stack);
		run("Duplicate...", "duplicate"); corrected_image_first = getImageID(); rename("First_stack");
		for (i=0; i < x.length; i++){
			setSlice(i+1); getStatistics(area, mean, min, max, std, histogram);
			run("Multiply...", "value=" +ratio_data[i]);
		}
			// --- Second stack	
		selectImage(second_raw_stack); 
		run("Duplicate...", "duplicate"); corrected_image_second = getImageID(); rename("Second_stack");
		for (i = 0; i < size_second_stack; i++ ){
			setSlice(i+1); getStatistics(area, mean, min, max, std, histogram);
			run("Multiply...", "value=" +ratio_data_second[i]);
		}
		selectImage(trim_stack); 
		saveAs("tiff", save_folder + "noBC -trimT -trimSP -raw_stack"); close();
		
		selectImage(first_raw_stack); close();
		selectImage(second_raw_stack); close();
		
		run("Concatenate...", "  image1=First_stack image2=Second_stack "); run("Set... ", "zoom=33");
		saveAs("tiff", save_folder + "BC -trimT -trimSP -raw_stack");
		trim_stack = getImageID(); // using the same name
	
	} else {
	// --- Electrical Stimulation: YES
	// --- Fit: NO
		selectImage(trim_stack); close();

		run("Concatenate...", "  image1=First_stack image2=Second_stack "); run("Set... ", "zoom=33");
		saveAs("tiff", save_folder + "noBC -trimT -trimSP -raw_stack");
		trim_stack = getImageID(); // using the same name
	}

} else {
	// --- Electrical Stimulation: NO
	selectImage(trim_stack); 
	//run("Duplicate...", "duplicate"); 
	All_stack = getImageID();
	run("Plot Z-axis Profile"); Plot.getValues(x,y); Z_profile = getImageID(); 
	biexp = "y = a + b*exp(-(c*x)) + d*exp(-(e*x))";
	initialGuesses = newArray(1, 1, 1, 1, 1);
	Fit.doFit(biexp, x, y, initialGuesses); Fit.plot; Z_profile_fit = getImageID();
	Fit.logResults;
	Offset = Fit.p(0); Coeff_1 = Fit.p(1); Coeff_2 = Fit.p(3); Tau_1 = Fit.p(2); Tau_2 = Fit.p(4); R_2 = Fit.rSquared;
	
	selectImage(Z_profile); close();
	waitForUser("Fit Review","Review the Fitting process.\nPress OK to proceed.");
	
	Dialog.create("MACRO FIT BACKDOOR");
	Dialog.addCheckbox("Would you like to proceed with bleaching correction?", false);
	Dialog.show();
	Fit_proceeding = Dialog.getCheckbox();
	
	
		
	if (Fit_proceeding) {
		// --- Electrical Stimulation: NO
		// --- FIT: YES

		reference_ratio = Fit.f(x[0]); // at time 0
		x_data = newArray(x.length);
	
		for (j = 0; j < x.length; j++){
			x_data [j] = Fit.f(x[j]);
			ratio_data[j] = reference_ratio/Fit.f(x[j]);
		}
	
		selectImage(All_stack);
		saveAs("tiff", save_folder + "noBC -trimT -trimSP -raw_stack");
		
		for (i=0; i < x.length; i++){
			setSlice(i+1); getStatistics(area, mean, min, max, std, histogram);
			run("Multiply...", "value=" +ratio_data[i]);
		}
		selectImage(Z_profile_fit); close();
		selectImage(All_stack); run("Set... ", "zoom=33");
		saveAs("tiff", save_folder + "BC -trimT -trimSP -raw_stack");
		trim_stack = getImageID(); // using the same name
		
	} else {
		// --- Electrical Stimulation: NO
		// --- FIT: NO

		selectImage(Z_profile_fit); close();
		selectImage(All_stack); run("Set... ", "zoom=33");
		saveAs("tiff", save_folder + "noBC -trimT -trimSP -raw_stack");
		trim_stack = getImageID(); // using the same name
		
	}
}


// -----------------------------------------------------------




// -----------------------------------------------------------
// CLEANING THE STACK
selectImage(trim_stack);
run("Duplicate...", "duplicate"); run("Set... ", "zoom=33"); OG_stack = getImageID();
selectImage(trim_stack);

	// --- Removing some noise
number_frames = nSlices();
setBatchMode(true);
for (i = 1; i <= number_frames; i++) {
	run("Set... ", "zoom=33");
	setSlice(i);
	run("FFT");
	rename("FFT_"+i);
	run("Make Circular Selection...", "radius="+radius);
	run("Clear");
	run("Select None");
	run("Inverse FFT");
	close("FFT_"+i);
	selectImage(trim_stack);
}

run("Images to Stack", "method=[Copy (center)] name=Stack title=Inverse use");
rename("iFFT_radius_"+radius); run("Set... ", "zoom=33");
setBatchMode(false);
selectImage(trim_stack); close();
run("Enhance Contrast", "saturated=0.35");

trim_stack_FFT = getImageID();
selectImage(trim_stack_FFT); run("Set... ", "zoom=33");

	// --- Cleaning/Homogeneizing the background
do {
	selectImage(trim_stack_FFT); 
	run("Duplicate...", "duplicate"); run("Set... ", "zoom=33");
	
	SB_trim_stack_FFT = getImageID();
	rolling_ball = 50;
	run("Subtract Background...", "rolling=50 stack"); // 50pixels is the "biggest" objects
	run("Enhance Contrast", "saturated=0.35");
	waitForUser("Review","Review your stack and Press OK");
	
	Dialog.create("Review feedback");
	Dialog.addCheckbox("Are you satisfied", false);
	Dialog.show();
	Feedback = Dialog.getCheckbox();
	if (Feedback == false) {
		selectImage(SB_trim_stack_FFT); close();
	}
} while (Feedback == false);

selectImage(trim_stack_FFT); close();
selectImage(SB_trim_stack_FFT); run("Set... ", "zoom=33");

	// --- Improve contrast of objects
		// --- Reset of the offset
/*setTool("rectangle"); run("Enhance Contrast", "saturated=0.35");
waitForUser("Subtraction","Draw a rectangle in the background -AVOID the events \nPress OK");
roiManager("Add"); roiManager("select",0); roiManager("rename", "background subtraction ROI");
roiManager("Save", save_folder + "_ROI_BG_subtraction.zip");

for (i=1; i <= nSlices(); i++){
	run("Restore Selection");
	setSlice(i);
	getStatistics(area, mean, min, max, std, histogram);
	run("Select None");
	run("Subtract...", "value=mean");
}
roiManager("Show All without labels");
roiManager("Show None"); roiManager("reset");*/
run("Gaussian Blur...", "sigma=5 stack");
Projected_Final_stack = getImageID();
//SB_trim_stack_FFT_GB = getImageID();
//selectImage(SB_trim_stack_FFT_GB); run("Set... ", "zoom=33");

//rename("Trim_stack_FFT_GB"); 
//Final_stack = getImageID();
	// --- Subtract from the final Stack
//for (i=1; i <= nSlices(); i++){
	//selectImage(Final_stack);
	//roiManager("select",0);
	//setSlice(i);
	//getStatistics(area, mean, min, max, std, histogram);
	//run("Select None");
	//run("Subtract...", "value=mean");
//}


	// --- PROJECTION METHODs
//Projected_Final_stack = getImageID();
selectImage(Projected_Final_stack);
run("Z Project...", "projection=[Max Intensity]"); MAX_trim_projection = getImageID(); rename("MAX"); run("32-bit"); 
selectImage(Projected_Final_stack);
run("Z Project...", "projection=[Standard Deviation]"); SD_trim_projection = getImageID(); rename("STD"); 
selectImage(Projected_Final_stack); close();

		// --- SUM METHOD (MAX + SD)projection
imageCalculator("Add create 32-bit", "MAX","STD"); rename("SUM_Method"); run("Set... ", "zoom=33");
saveAs("tiff", save_folder + "Projection_forWEKA"); projection_for_weka_file = getImageID();

// new addtition to sharpen objects
width = getWidth(); height = getHeight();
min_dimension = minOf(width, height)/10;
run("Unsharp Mask...", "radius=min_dimension mask=0.90");
//set the min value to 0. Images after unsharp mask filter contain negative int pixel values
getStatistics(area, mean, min, max);
run("Add...", "value=min");

selectImage(MAX_trim_projection); close();
selectImage(SD_trim_projection); close();


//--------------------------------------------------------------------------------



// -----------------------------------------------------------
// WEKA SEGMENTATION

// ------------- CALLING WEKA TO GENERATE FINAL SEGMENTATION
// ---

run("Trainable Weka Segmentation");
wait(3000);
call("trainableSegmentation.Weka_Segmentation.loadClassifier", "D://Blandine/classifer With balance_ on sum (14).model");
call("trainableSegmentation.Weka_Segmentation.getResult");
saveAs("tiff", save_folder + "results_weka"); run("Set... ", "zoom=33"); result_weka_file = getImageID(); 
close("Trainable*");

// ------------- ANALYSIS: WORKING ON WEKA FINAL RESULTS
// ---

// --- CREATING MASKs
selectImage(result_weka_file); run("Set... ", "zoom=33");
weka_width = getWidth(); weka_height = getHeight();
setBatchMode(true);
for (i=0; i<3; i++) {
	selectImage(result_weka_file);
	run("Duplicate...", " "); rename("Threshold-"+i);
	setThreshold(0, i); 
	run("Convert to Mask", "method=Default background=Light");
}
selectImage(result_weka_file); close();
run("Images to Stack", "name=Stack title=Threshold use"); 
setBatchMode("exit and display"); run("Set... ", "zoom=33");

// --- ANALYSE PARTICLES: SIZE EXCLUSION
	// --- Analyze Particles -settings
run("Set Measurements...", "area center nan redirect=None decimal=3");
setForegroundColor(255, 255, 255); setBackgroundColor(0, 0, 0);
roiManager("reset"); print("\\Clear");
stack_threshold = getImageID(); threshold_range = nSlices();
count = newArray(threshold_range); // Counting each ROI category
structure_name = newArray("hole_", "in_donut_", "out_donut_");
total = 0;

	// --- Analyze Particles -ROI generator
selectImage(stack_threshold); run("Set... ", "zoom=33");
for (i=0; i<threshold_range; i++) {
	setSlice(i+1); run("Analyze Particles...", "size=300-Infinity add");
	count[i] = roiManager("count");
	roiManager("Show All without labels");
	roiManager("Show None");
	if (count[i]!=0) { //number of ROIs should be higher than 0
		for (j=0; j < count[i]; j++) {
			roiManager("select",j);
			roiManager("rename", structure_name[i]+IJ.pad(j+1,3));
			roiManager("Deselect"); run("Select None");
		}
	roiManager("Save", save_folder +"ROIs_"+structure_name[i]+".zip");
	roiManager("reset");
	total += count[i]; //total number of ROIs
	}
}
selectImage(stack_threshold); close();

// --- ANALYSE PARTICLES: SORTING AND SAVING
	// --- Settings
run("Set Measurements...", "area mean integrated area_fraction nan redirect=None decimal=3");
parameter = newArray ("IntDensity","Mean", "area");
method = newArray ("Additive", "Exclusive");
setForegroundColor(0, 0, 0); setBackgroundColor(255, 255, 255);

selectImage(OG_stack);

setTool("rectangle"); run("Enhance Contrast", "saturated=0.35");
//roiManager("open", save_folder +"_ROI_BG_subtraction.zip");

/*for (i=1; i <= nSlices(); i++){
	//selectImage(OG_stack);
	roiManager("select",0);
	setSlice(i);
	getStatistics(area, mean, min, max, std, histogram);
	run("Select None");
	run("Subtract...", "value=mean");
}
*/

F_OG_stack = getImageID();	
roiManager("reset");

	// --- ADDITIVE MEASUREMENTS *HOLE *HOLE+IN_DONUT *HOLE+IN_DONUT+OUT_DONUT

	// --- Intensity Measurements: Additive structures
	r = 0; //additive
	
	for (m = 0; m < lengthOf(structure_name); m ++) {
		roiManager("reset");
		if (count[m]!=0) {
			roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");
			cleaning_intensity (count_, save_folder, m, r); // IntDensity
			run("Select None");
		}
	}
	
	// --- Mean Measurements: Additive structures
	for (m = 0; m < lengthOf(structure_name); m ++) {
		roiManager("reset");
		if (count[m]!=0) {
			roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");
			cleaning_mean (count_, save_folder, m, r); // Mean
			run("Select None");
		}
	}
	
	run("Clear Results");
	roiManager("reset");
	// --- Collecting Area information of Additive structures
	run("Set Measurements...", "area display nan redirect=None decimal=3");
	for (m = 0; m < lengthOf(structure_name); m ++) {
		if (count[m]!=0) {
			roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");
			array_area = newArray(count_);
			for (i=0; i < count_; i++) {
				roiManager("select",i); run("Measure");
			}
		saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[2]+".txt");
		run("Clear Results");
		}
		roiManager("reset"); run("Select None");
	}


// ----
run("Clear Results");
roiManager("reset");
run("Select None");
selectImage(F_OG_stack);

// ----
	// --- EXCLUSIVE MEASUREMENTS *HOLE *IN_DONUT-HOLE *OUT_DONUT-IN_DONUT-HOLE
	
	// --- Intensity Measurements: Single structures
r = 1; // Single structures

		// --- HOLES
m = 0;
if (count[m]!=0) {
	roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");
	selectionROI(count_); run("Fill", "stack"); // Filling up donuts with 0
}
F_OG_stack_donut = getImageID();
run("Select None");
roiManager("Deselect"); roiManager("reset");
run("Clear Results");
		
		// --- IN_DONUT-HOLES
m = 1;
selectImage(F_OG_stack_donut); number_frames = nSlices();
if (count[m]!=0) {
	roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");	
	run("Select None"); roiManager("Deselect");	
	run("Set Measurements...", "area area_fraction display nan redirect=None decimal=3");
			// --- Area
	coefficient = newArray(count_);
	abs_area = newArray(count_); 
	true_area = newArray(count_);

	for (i=0; i < count_; i++) {
		roiManager("select",i); run("Measure");
		coefficient [i] = getResult("%Area",i);
		abs_area [i] = getResult("Area",i);
		true_area [i] = abs_area[i] * coefficient[i]/100;
		setResult("True Area", i, true_area[i]);			
	}
	Table.deleteColumn("Area"); Table.deleteColumn("%Area");
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[2]+".txt");
}
// -----
run("Clear Results");
run("Select None");
roiManager("Deselect");	
// -----
			// --- Intensity and Mean
if (count[m]!=0) {
	run("Set Measurements...", "mean integrated display nan redirect=None decimal=3");
	Table.create(parameter[0]+"_"+method[r]+"_"+structure_name[m]); //true Intensity 
	Table.create(parameter[1]+"_"+method[r]+"_"+structure_name[m]); //true Mean

	for (j=0; j < count_; j++) {
		temp_storage_int = newArray(number_frames);
		temp_storage_mean = newArray(number_frames);
		roiManager("select",j);
		for (i=0; i< number_frames; i++) {
			setSlice(i+1); run("Measure");
			selectWindow("Results");
			temp_storage_int [i] = getResult("RawIntDen",i);
			temp_storage_mean [i] = getResult("Mean",i);
		}
		run("Clear Results");
		run("Select None"); roiManager("Deselect");
		selectWindow(parameter[0]+"_"+method[r]+"_"+structure_name[m]);
		Table.setColumn(parameter[0]+"_"+method[r]+"_"+structure_name[m]+IJ.pad(j+1,3), temp_storage_int);
		selectWindow(parameter[1]+"_"+method[r]+"_"+structure_name[m]);
		Table.setColumn(parameter[1]+"_"+method[r]+"_"+structure_name[m]+IJ.pad(j+1,3), temp_storage_mean);
	}
	selectWindow(parameter[0]+"_"+method[r]+"_"+structure_name[m]);
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[0]+".txt");
	close("ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[0]+".txt");
	selectWindow(parameter[1]+"_"+method[r]+"_"+structure_name[m]);
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[1]+".txt");
	close("ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[1]+".txt");
}

// -----
run("Clear Results");
run("Select None");
roiManager("Deselect");	
// -----

		// --- OUT_DONUT-IN_DONUT-HOLES
m = 1; count_ = roiManager("count");
if (count[m]!=0) {
	selectionROI(count_); run("Fill", "stack"); // Filling up donuts with 0
}
FF_OG_stack_donut = getImageID();
run("Select None");
roiManager("Deselect"); roiManager("reset");
run("Clear Results");
//---
m = 2;
selectImage(FF_OG_stack_donut);
if (count[m]!=0) {
	roiManager("open", save_folder +"ROIs_"+structure_name[m]+".zip"); count_ = roiManager("count");	
	run("Select None");
	roiManager("Deselect");	
	run("Set Measurements...", "area area_fraction display nan redirect=None decimal=3");
			// --- Area
	coefficient = newArray(count_);
	abs_area = newArray(count_); 
	true_area = newArray(count_);

	for (i=0; i < count_; i++) {
		roiManager("select",i); run("Measure");
		coefficient [i] = getResult("%Area",i);
		abs_area [i] = getResult("Area",i);
		true_area [i] = abs_area[i] * coefficient[i]/100;
		setResult("True Area", i, true_area[i]);			
	}
	selectWindow("Results");
	Table.deleteColumn("Area"); Table.deleteColumn("%Area");
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[2]+".txt");
}
// -----
run("Clear Results");
run("Select None");
roiManager("Deselect");	
// -----
			// --- Intensity and Mean
if (count[m]!=0) {
	run("Set Measurements...", "mean integrated display nan redirect=None decimal=3");
	Table.create(parameter[0]+"_"+method[r]+"_"+structure_name[m]); //true Intensity 
	Table.create(parameter[1]+"_"+method[r]+"_"+structure_name[m]); //true Mean

	for (j=0; j < count_; j++) {
		temp_storage_int = newArray(number_frames);
		temp_storage_mean = newArray(number_frames);
		roiManager("select",j);
		for (i=0; i< number_frames; i++) {
			setSlice(i+1); run("Measure");
			selectWindow("Results");
			temp_storage_int [i] = getResult("RawIntDen",i);
			temp_storage_mean [i] = getResult("Mean",i);
		}
		selectWindow("Results"); run("Clear Results");
		run("Select None"); roiManager("Deselect");
		selectWindow(parameter[0]+"_"+method[r]+"_"+structure_name[m]);
		Table.setColumn(parameter[0]+"_"+method[r]+"_"+structure_name[m]+IJ.pad(j+1,3), temp_storage_int);
		selectWindow(parameter[1]+"_"+method[r]+"_"+structure_name[m]);
		Table.setColumn(parameter[1]+"_"+method[r]+"_"+structure_name[m]+IJ.pad(j+1,3), temp_storage_mean);
	}
	selectWindow(parameter[0]+"_"+method[r]+"_"+structure_name[m]);
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[0]+".txt");
	close("ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[0]+".txt");
	selectWindow(parameter[1]+"_"+method[r]+"_"+structure_name[m]);
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[1]+".txt");
	close("ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[1]+".txt");
}








// -----------------------------------------------------------
// ---FUNCTIONS
function selectionROI (n) {
	roi_array = newArray(n);
	for (i=0; i<n; i++) {
		roi_array[i] = i;
	}
	roiManager("select",roi_array); roiManager("Combine");
}

function cleaning_intensity (count_, dir, m, r) {
run("Set Measurements...", "area mean integrated area_fraction nan redirect=None decimal=3");
roiManager("Multi Measure");
	for (i=1; i < count_+1; i++) {
		Table.deleteColumn("Area("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("Mean("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("IntDen("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("%Area("+structure_name[m]+IJ.pad(i,3)+")");
	} Table.update();
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[0]+".txt");
	run("Clear Results"); roiManager("reset");
	run("Select None");
}

function cleaning_mean (count_, dir, m, r) {
run("Set Measurements...", "area mean integrated area_fraction nan redirect=None decimal=3");
roiManager("Multi Measure");
	for (i=1; i < count_+1; i++) {
		Table.deleteColumn("Area("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("RawIntDen("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("IntDen("+structure_name[m]+IJ.pad(i,3)+")");
		Table.deleteColumn("%Area("+structure_name[m]+IJ.pad(i,3)+")");
	} Table.update();
	saveAs("results", save_folder +"ROIs_"+structure_name[m]+"_"+method[r]+"_"+parameter[1]+".txt");
	run("Clear Results"); roiManager("reset");
	run("Select None");
}

function MessageLog(nFrames) {
// --- RESET THE LOG
print("\\Clear");
print("-------- USER's INPUT --------");
if (Proceeding) {
	print("--- There are "+nFrames+" in this stack after trimming in space and in time.");
	print("-- Number of Frames removed prior to analysis: "+trim);
	if (Addition) {
		print("-- Position of the Electrical stimulation: "+split_point);
		if (Fit_proceeding) {
			print("--- ELECTRICAL STIMULATION: YES ---");
			print("--- BLEACHING CORRECTION: YES ---");
			print("-- Number of frames removed around the Electrical Stimulation Peak: "+removal_points);
		} else {
			print("--- ELECTRICAL STIMULATION: YES ---");
			print("--- BLEACHING CORRECTION: NO ---");
		}
	} else {
		if (Fit_proceeding) {
			print("--- ELECTRICAL STIMULATION: NO ---");
			print("--- BLEACHING CORRECTION: YES ---");
		} else {
			print("--- ELECTRICAL STIMULATION: NO ---");
			print("--- BLEACHING CORRECTION: NO ---");
		}
	}
	
print("-------- FITTING PARAMETERS --------");
print("Bi-Exponential FIT: y(x) = Offset + Coeff_1*exp(-(Tau_1*x)) + Coeff_2*exp(-(Tau_2*x))"); 
print("Offset: " + Fit.p(0) +"\n"+ "Coeff_1: " +Fit.p(1)+"\n"+ "Coeff_2: " +Fit.p(3)+"\n"+ "Tau_1: "+Fit.p(2)+"\n"+ "Tau_2: "+Fit.p(4)+"\n"+ "R_2: "+Fit.rSquared);


print("-------------- ROIs ----------------");
print("Minimal size to be considered as a ROI: 300 pixels");
for (i=0; i <threshold_range; i++) {
	print("There are "+count[i]+" ROI(s) that correspond(s) to "+structure_name[i]);
}

} else {
	print("MACRO STOPPED");
}

saveAs("Text", save_folder + name_file +"_FIT_Summary");
}