# Copyright 2016 Trimble Navigation Limited
# Licensed under the MIT license

require 'sketchup.rb'
require 'set'

module Ittay
	CommandWrapper ||= Struct.new(:command, :appear)
	def self.add_submenu(menu)
		menu.add_submenu("Ittay's")
	end	
		
	def self.register_command(command, &block)
 		@submenuenu ||= add_submenu(UI.menu('Plugins'))
		begin
			@submenuenu.add_item(command)
		rescue Exception => e 
			puts "exception @{e.inspect}"
			@submenuenu = UI.menu('Plugins').add_submenu("Ittay's")
			@submenuenu.add_item(command)
		end
		
		@handlers_count ||= UI.add_context_menu_handler(&(method(:handle_context_menu)))
		@commands ||= []
		
		@commands.push(CommandWrapper.new(command, block))
	end
	
	def self.handle_context_menu(menu)
		model = Sketchup.active_model
		menu = add_submenu(menu)
		@commands.each do |cw|
			if cw.appear.nil? || cw.appear.call(model.selection)
				menu.add_item(cw.command)
			end
		end
	end
	
  module Extensions
	def self.rgrep(what = nil, &block)
		model = Sketchup.active_model
		selection = model.selection
		arr = grep_recursion(selection, what.nil? ? block : what, [])
		selection.clear
		selection.add(arr)
	end
	
	def self.grep_recursion(entities, what, arr)
		if entities.nil?
		  # empy on purpose
		else
		  entities.each do |entity|
			if what === entity
				arr.push(entity)
			end
			if entity.is_a? Sketchup::Group
				grep_recursion(entity.entities, what, arr)
			end
			if entity.is_a? Sketchup::ComponentInstance
				grep_recursion(entity.definition.entities, what, arr)
			end
		  end
		end
		arr
	end
	
	def self.scatter(entities, compdef, count, &randomizer)
		model = Sketchup.active_model
		model.start_operation "Scatter", true; 
		count.times do 
			# point = randomizers.inject(Struct.new(:point, :payload).new(Geom::Point3d.new, nil)) do |data, randomizer|
			#	randomizer.(data)
			#	data
			# end.point
			point = randomizer.call()
			puts "Inserting at #{point}" if @debug
			entities.add_instance(compdef, Geom::Transformation.new(point))
		end
		model.commit_operation
	end
	
	def self.lecture_scatter(entities, compdef, count, centers, lengths)
		scatter(entities, compdef, count) do 
			i = rand(centers.length)
			[:x, :y, :z].map do |prop| 
				centers[i].send(prop) + 
				#+ (Math.sin(rand(-90..0).degrees) + 1) 
				(1- Math.sqrt(rand(0..1000)/1000.0)) * 
					lengths[i].send(prop).sample
			end
		end
	end
	
    def self.rotate(right_projection_degree, left_projection_degree, back = false, reverse = false)
      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
      model.start_operation('Isometric Rotation', true)

	  top = Math::atan(Math::sqrt(Math::tan(right_projection_degree)/Math::tan(left_projection_degree))) # 45 degrees for 30/30 isometric
	  right = Math::asin(Math::tan(right_projection_degree) * Math::cos(top) / Math::sin(top)) # # (~35.264389) for 30/30 isometric
	  
	  if back
		top += Math::PI
		right = -right
	  end
	  
	  model.selection.each do |entity|
	    corner = entity.bounds.corner(0)
		t1 = Geom::Transformation.rotation(corner, [0,0,1], top)
		t2	 = Geom::Transformation.rotation(corner, [1,0,0], right) 
		
		t = t2 * t1
		if reverse
			t.invert!
		end
		entity.transform!(t)
	  end
      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
	
	end


    # This method rotates the selection
    def self.rotate_isometric
		rotate(30.degrees, 30.degrees)
	end
	
	def self.rotate_back_isometric
		rotate(30.degrees, 30.degrees, true)
    end

	def self.make_group
      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
      model.start_operation('Make Group', true)

	  group = model.entities.add_group(model.selection)

      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
    end

 
	
	
	
    # Here we add a menu item for the extension. Note that we again use a
    # load guard to prevent multiple menu items from accidentally being
    # created.
    unless file_loaded?(__FILE__)
	  
	 # We add the menu item directly to the root of the menu in this example.
      # But if you plan to add multiple items per extension we recommend you
      # group them into a sub-menu in order to keep things organized.
      Ittay.register_command(UI::Command.new('Rotate Isometric') {self.rotate_isometric})
	  
	  Ittay.register_command(UI::Command.new('Rotate Isometric^-1') {self.rotate_back_isometric})
	  
	  Ittay.register_command(UI::Command.new('Make Group') {self.make_group})
	  
      file_loaded(__FILE__)
    end

  end # module 
end # module 
