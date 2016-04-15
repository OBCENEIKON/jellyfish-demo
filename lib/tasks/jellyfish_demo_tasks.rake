def sample_data(file)
  puts "-- Loading #{file.titlecase}"
  data = YAML.load_file(File.join [Rails.root, 'db', 'data', 'sample', [file, 'yml'].join('.')])
  return data unless block_given?
  data.each { |d| yield d }
end

namespace :setup do
  desc 'Sets up simple dataset'
  task simple: :environment do
    sample_data('organizations').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Organization.create(data).tap do |org|
        org.alerts.create(alerts) unless alerts.nil?
      end]
    end

    users = sample_data('staff').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['first_name']} #{data['last_name']}"
      [data.delete('_assoc'), Staff.create(data).tap do |user|
        user.alerts.create(alerts) unless alerts.nil?
      end]
    end

    sample_data('product_categories').map do |data|
      puts "  #{data['name']}"
      [data.delete('_assoc'), ProductCategory.create(data)]
    end

    sample_data('project_questions').map do |data|
      puts "  #{data['question']}"
      [data.delete('_assoc'), ProjectQuestion.create(data)]
    end

    sample_data('demo_projects').map do |data|
      approvals = data.delete 'approvals'
      alerts = data.delete 'alerts'
      answers = data.delete 'answers'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Project.create(data).tap do |project|
        project.alerts.create(alerts) unless alerts.nil?
        unless approvals.nil?
          approvals = approvals.map do |approval|
            user = users.assoc(approval.delete('staff')).last
            approval.merge(staff: user)
          end
          project.approvals.create approvals
        end
        unless answers.nil?
          answers = answers.map do |answer|
            question = project_questions.assoc(answer.delete('question')).last
            answer.merge name: question['uuid'], value_type: 'string'
          end
          project.answers.create answers
        end
      end]
    end
  end

  desc 'Generates demo data'
  task old: :environment do

    # generate provider data from demo registered provider
    provider_data = {
        'type'=>'JellyfishDemo::Provider::Demo',
        'registered_provider'=>RegisteredProvider.where(name: 'Demo').first,
        'name'=>'Demo Provider',
        'description'=>'Provider for the Demo',
        'active'=>true,
        'tag_list'=>['demo']
    }
    providers = [['demo', Provider.create(provider_data)]]

    orgs = sample_data('organizations').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Organization.create(data).tap do |org|
        org.alerts.create(alerts) unless alerts.nil?
      end]
    end

    users = sample_data('staff').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['first_name']} #{data['last_name']}"
      [data.delete('_assoc'), Staff.create(data).tap do |user|
        user.alerts.create(alerts) unless alerts.nil?
      end]
    end

    categories = sample_data('product_categories').map do |data|
      puts "  #{data['name']}"
      [data.delete('_assoc'), ProductCategory.create(data)]
    end

    products = sample_data('products').map do |data|
      answers = data.delete 'answers'
      product_type = ProductType.find_by uuid: data.delete('product_type')
      provider = providers.assoc(data.delete 'provider').last
      data.merge! product_type: product_type, provider: provider
      puts "  #{data['name']}"
      [data.delete('_assoc'), Product.create(data).tap do |product|
        product.answers.create(answers) unless answers.nil?
      end]
    end

    project_questions = sample_data('project_questions').map do |data|
      puts "  #{data['question']}"
      [data.delete('_assoc'), ProjectQuestion.create(data)]
    end

    projects = sample_data('projects').map do |data|
      approvals = data.delete 'approvals'
      alerts = data.delete 'alerts'
      answers = data.delete 'answers'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Project.create(data).tap do |project|
        project.alerts.create(alerts) unless alerts.nil?
        unless approvals.nil?
          approvals = approvals.map do |approval|
            user = users.assoc(approval.delete 'staff').last
            approval.merge(staff: user)
          end
          project.approvals.create approvals
        end
        unless answers.nil?
          answers = answers.map do |answer|
            question = project_questions.assoc(answer.delete 'question').last
            answer.merge name: question['uuid'], value_type: 'string'
          end
          project.answers.create answers
        end
      end]
    end

    sample_data 'services' do |data|
      @setup_price = 0
      @hourly_price = 0
      @monthly_price = 0

      productList = data.delete 'products'
      services = productList.map do |orderProduct|
        product = products.assoc(orderProduct.delete('product'))
        product = product.last

        service_outputs = orderProduct.delete 'service_outputs'
        orderProduct['uuid'] = SecureRandom.uuid
        [orderProduct.delete('_assoc'), Service.create(orderProduct).tap do |service|
          puts "  #{service['name']}"
          service.service_outputs.create(service_outputs) unless service_outputs.nil?
          service.product_id = product.id
          @setup_price += product.setup_price
          @hourly_price += product.hourly_price
          @monthly_price += product.monthly_price
        end]
      end

      order_params = {
          staff: users.assoc(data.delete('staff')).last,
          project: projects.assoc(data.delete('project')).last,
          setup_price: @setup_price,
          hourly_price: @hourly_price,
          monthly_price: @monthly_price
      }
      order = Order.create(order_params)

      services.map do |service|
        service.last.order_id = order.id
        service.last.save
      end
    end

    sample_data 'wizard_questions' do |data|
      answers = data.delete 'answers'
      puts "  #{data['text']}"
      [data.delete('_assoc'), WizardQuestion.create(data).tap { |q| q.wizard_answers.create answers }]
    end

    groups = sample_data('groups').map do |data|
      group_staff = data.delete('group_staff') || []
      puts "  #{data['name']}"
      [data.delete('_assoc'), Group.create(data).tap do |group|
        next if group_staff.nil?
        group_staff.each do |staff|
          group.staff << users.assoc(staff).last
        end
      end]
    end

    roles = sample_data('roles').map do |data|
      puts "  #{data['name']}"
      [data.delete('_assoc'), Role.create(data)]
    end

    sample_data 'memberships' do |data|
      project = projects.assoc(data['project']).last
      group = groups.assoc(data['group']).last
      role = roles.assoc(data['role']).last
      Membership.create(project: project, group: group, role: role)
    end
  end

  desc 'Generates demo data'
  task demo: :environment do
    # generate provider data from demo registered provider
    provider_data = {
        'type'=>'JellyfishDemo::Provider::Demo',
        'registered_provider'=>RegisteredProvider.where(name: 'Demo').first,
        'name'=>'Demo Provider',
        'description'=>'Provider for the Demo',
        'active'=>true,
        'tag_list'=>['demo']
    }
    providers = [['demo', Provider.create(provider_data)]]

    orgs = sample_data('organizations').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Organization.create(data).tap do |org|
        org.alerts.create(alerts) unless alerts.nil?
      end]
    end

    users = sample_data('staff').map do |data|
      alerts = data.delete 'alerts'
      puts "  #{data['first_name']} #{data['last_name']}"
      [data.delete('_assoc'), Staff.create(data).tap do |user|
        user.alerts.create(alerts) unless alerts.nil?
      end]
    end

    categories = sample_data('product_categories').map do |data|
      puts "  #{data['name']}"
      [data.delete('_assoc'), ProductCategory.create(data)]
    end

    products = sample_data('products').map do |data|
      answers = data.delete 'answers'
      # product types are hardcoded to demo compute in sample db data
      product_type = ProductType.find_by uuid: data.delete('product_type')
      provider = providers.assoc(data.delete 'provider').last
      data.merge! product_type: product_type, provider: provider
      puts "  #{data['name']}"
      [data.delete('_assoc'), Product.create(data).tap do |product|
        product.answers.create(answers) unless answers.nil?
      end]
    end

    project_questions = sample_data('project_questions').map do |data|
      puts "  #{data['question']}"
      [data.delete('_assoc'), ProjectQuestion.create(data)]
    end

    projects = sample_data('projects').map do |data|
      approvals = data.delete 'approvals'
      alerts = data.delete 'alerts'
      answers = data.delete 'answers'
      puts "  #{data['name']}"
      [data.delete('_assoc'), Project.create(data).tap do |project|
        project.alerts.create(alerts) unless alerts.nil?
        unless approvals.nil?
          approvals = approvals.map do |approval|
            user = users.assoc(approval.delete 'staff').last
            approval.merge(staff: user)
          end
          project.approvals.create approvals
        end
        unless answers.nil?
          answers = answers.map do |answer|
            question = project_questions.assoc(answer.delete 'question').last
            answer.merge name: question['uuid'], value_type: 'string'
          end
          project.answers.create answers
        end
      end]
    end

    sample_data 'services' do |data|
      @setup_price = 0
      @hourly_price = 0
      @monthly_price = 0

      productList = data.delete 'products'
      services = productList.map do |orderProduct|
        product = products.assoc(orderProduct.delete('product'))
        product = product.last

        service_outputs = orderProduct.delete 'service_outputs'
        orderProduct['uuid'] = SecureRandom.uuid
        [orderProduct.delete('_assoc'), Service.create(orderProduct).tap do |service|
          puts "  #{service['name']}"
          service.service_outputs.create(service_outputs) unless service_outputs.nil?
          service.product_id = product.id
          @setup_price += product.setup_price
          @hourly_price += product.hourly_price
          @monthly_price += product.monthly_price
        end]
      end

      order_params = {
          staff: users.assoc(data.delete('staff')).last,
          project: projects.assoc(data.delete('project')).last,
          setup_price: @setup_price,
          hourly_price: @hourly_price,
          monthly_price: @monthly_price
      }
      order = Order.create(order_params)

      services.map do |service|
        service.last.order_id = order.id
        service.last.save
      end
    end

    sample_data 'wizard_questions' do |data|
      answers = data.delete 'answers'
      puts "  #{data['text']}"
      [data.delete('_assoc'), WizardQuestion.create(data).tap { |q| q.wizard_answers.create answers }]
    end

    groups = sample_data('groups').map do |data|
      group_staff = data.delete('group_staff') || []
      puts "  #{data['name']}"
      [data.delete('_assoc'), Group.create(data).tap do |group|
        next if group_staff.nil?
        group_staff.each do |staff|
          group.staff << users.assoc(staff).last
        end
      end]
    end

    roles = sample_data('roles').map do |data|
      puts "  #{data['name']}"
      [data.delete('_assoc'), Role.create(data)]
    end

    sample_data 'memberships' do |data|
      project = projects.assoc(data['project']).last
      group = groups.assoc(data['group']).last
      role = roles.assoc(data['role']).last
      Membership.create(project: project, group: group, role: role)
    end
  end
end
